// FILE: mmschat-codex-rollout.js
// Purpose: Discovers and normalizes local Codex CLI/TUI rollout sessions for MMSChat.
// Layer: Transcript metadata helper
// Exports: Bounded Codex rollout discovery and detail transcript snapshots.
// Depends on: crypto, fs, os, path

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");

const TRANSCRIPT_SOURCE_CODEX_ROLLOUT = "codex-rollout";
const NATIVE_PATH_STATE_CONFIRMED = "confirmed";
const NATIVE_PATH_STATE_UNAVAILABLE = "unavailable";
const MAX_DISCOVERY_FILES = 80;
const MAX_DISCOVERY_FILE_BYTES = 512_000;
const MAX_DISCOVERY_TITLE_LENGTH = 96;
const MAX_TEXT_LENGTH = 12_000;
const MAX_TOOL_PREVIEW_LENGTH = 4_000;
const MAX_DETAIL_MESSAGES = 500;

// Patterns that identify injected bootstrap/system/developer context text.
// These should not be rendered as user chat bubbles or counted toward titles.
const BOOTSTRAP_CONTEXT_PATTERNS = [
  /^\s*#\s*AGENTS\.md\b/im,
  /AGENTS\.md\s*instructions/i,
  /<INSTRUCTIONS>/i,
  /<instructions>/i,
  /<environment_context>/i,
  /<permissions\b/i,
  /<skills_instructions>/i,
  /<plugins_instructions>/i,
  /MCP\s+(server|startup|diagnostic)/i,
  /\[MCP\]/i,
  /^system\s+prompt\s*:/im,
  /^developer\s+instructions\s*:/im,
  /You are (powered by|an AI)\s/i,  // Model identity preamble / bootstrap role injection
];

function isBootstrapContextText(text) {
  if (!text) return false;
  return BOOTSTRAP_CONTEXT_PATTERNS.some((pattern) => pattern.test(text));
}

function isPlaceholderReasoning(text) {
  if (!text) return true;
  const trimmed = text.trim();
  if (!trimmed) return true;
  // "Thinking..." is the placeholder fallback
  if (trimmed === "Thinking..." || trimmed === "Thinking…") return true;
  return false;
}

function discoverCodexRolloutSessions(options = {}) {
  const fsImpl = options.fsImpl || fs;
  const maxFiles = readPositiveInteger(options.maxFiles) || MAX_DISCOVERY_FILES;
  const maxFileBytes = readPositiveInteger(options.maxFileBytes) || MAX_DISCOVERY_FILE_BYTES;
  const roots = resolveCodexSessionsRoots(options);

  // Collect and dedupe by file path hash so sessions do not appear twice
  // when multiple roots resolve to the same underlying path.
  const seenPathHashes = new Set();
  const candidates = [];
  for (const root of roots) {
    for (const candidate of collectRolloutFileCandidates(root, { fsImpl })) {
      const pathHash = digestText(normalizeRolloutIdentityPath(candidate.filePath, fsImpl));
      if (seenPathHashes.has(pathHash)) {
        continue;
      }
      seenPathHashes.add(pathHash);
      candidates.push(candidate);
    }
  }

  return candidates
    .sort(compareRolloutCandidates)
    .slice(0, maxFiles)
    .map((candidate) => buildDiscoveredCodexSession(candidate, { fsImpl, maxFileBytes }))
    .filter(Boolean);
}

function readCodexRolloutTranscriptSnapshot(options = {}) {
  const session = options.session || {};
  const match = findRolloutFileForSession(session, options);
  if (!match) {
    return buildCodexTranscriptSnapshot({ nativePathState: NATIVE_PATH_STATE_UNAVAILABLE });
  }

  const jsonlText = readBoundedTextFile(options.fsImpl || fs, match.filePath, options.maxDetailFileBytes);
  return parseCodexRolloutJsonl(jsonlText, {
    detail: true,
    fallbackSessionId: readNonEmptyString(session.metadata?.rolloutIdShort),
  }).transcript;
}

function isCodexRolloutSession(session) {
  return session?.provider === "codex" && session?.metadata?.source === TRANSCRIPT_SOURCE_CODEX_ROLLOUT;
}

function resolveCodexSessionsRoots(options = {}) {
  const env = options.env || process.env;
  const osImpl = options.osImpl || os;
  const explicitCodexHome = readNonEmptyString(options.codexHome) || readNonEmptyString(env.CODEX_HOME);
  const defaultRoot = path.join(osImpl.homedir(), ".codex", "sessions");

  if (explicitCodexHome) {
    const explicitRoot = path.join(path.resolve(explicitCodexHome), "sessions");
    // Include default ~/.codex/sessions fallback when it differs from the explicit path,
    // so that sessions stored at the default location are still discovered.
    const normalizedExplicit = path.resolve(explicitRoot);
    const normalizedDefault = path.resolve(defaultRoot);
    if (normalizedExplicit === normalizedDefault) {
      return [explicitRoot];
    }
    return [explicitRoot, defaultRoot];
  }

  return [defaultRoot];
}

function normalizeRolloutIdentityPath(filePath, fsImpl = fs) {
  if (!readNonEmptyString(filePath)) {
    return String(filePath || "");
  }
  try {
    if (typeof fsImpl.realpathSync === "function") {
      return fsImpl.realpathSync(filePath);
    }
  } catch {}
  return path.resolve(filePath);
}

function collectRolloutFileCandidates(root, { fsImpl = fs } = {}) {
  if (!safeExistsSync(fsImpl, root)) {
    return [];
  }

  const stack = [root];
  const candidates = [];
  while (stack.length > 0) {
    const current = stack.pop();
    const entries = safeReadDirents(fsImpl, current);
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry?.isDirectory?.()) {
        stack.push(fullPath);
        continue;
      }
      if (!entry?.isFile?.() || !entry.name.startsWith("rollout-") || !entry.name.endsWith(".jsonl")) {
        continue;
      }

      const stat = safeStatSync(fsImpl, fullPath);
      if (!stat) {
        continue;
      }
      candidates.push({
        filePath: fullPath,
        fileName: entry.name,
        mtime: stat.mtime instanceof Date ? stat.mtime.toISOString() : new Date().toISOString(),
        mtimeMs: toStatTime(stat),
        size: Number.isFinite(stat.size) ? stat.size : 0,
      });
    }
  }
  return candidates;
}

function buildDiscoveredCodexSession(candidate, { fsImpl = fs, maxFileBytes = MAX_DISCOVERY_FILE_BYTES } = {}) {
  const scanned = parseCodexRolloutJsonl(
    readBoundedTextFile(fsImpl, candidate.filePath, maxFileBytes),
    { detail: false }
  );
  if (!isCodexCliRolloutOrigin(scanned.sessionMeta)) {
    return null;
  }
  if (scanned.messageCount <= 0) {
    return null;
  }

  const rolloutId = readNonEmptyString(scanned.sessionMeta.id) || digestText(candidate.filePath).slice(0, 16);
  const cwd = readNonEmptyString(scanned.sessionMeta.cwd) || "~";
  // Prefer max(valid transcript timestamp, file mtime) so stale transcripts don't hide newer writes.
  // lastActivitySource tells the consumer whether the timestamp is from parsed records or file stat.
  const transcriptTimeMs = scanned.lastTimestamp ? new Date(scanned.lastTimestamp).getTime() : null;
  const fileMtimeMs = candidate.mtimeMs || (candidate.mtime ? new Date(candidate.mtime).getTime() : null);
  const effectiveTimeMs = (transcriptTimeMs !== null && fileMtimeMs !== null && transcriptTimeMs > fileMtimeMs)
    ? transcriptTimeMs
    : (fileMtimeMs || transcriptTimeMs || Date.now());
  const lastActivityAt = new Date(effectiveTimeMs).toISOString();
  const lastActivitySource = (transcriptTimeMs !== null && transcriptTimeMs >= (fileMtimeMs || 0)) ? "transcript" : "file_mtime";
  const createdAt = scanned.firstTimestamp || lastActivityAt;
  const pathHash = digestText(normalizeRolloutIdentityPath(candidate.filePath, fsImpl));

  // Build meaningful title from real user prompt, falling back to rollout ID only
  const userPrompt = readNonEmptyString(scanned.latestRealUserPrompt) || readNonEmptyString(scanned.firstRealUserPrompt);

  return {
    mmschatId: `mmschat_codex_${pathHash.slice(0, 24)}`,
    nativeClaudeSessionId: null,
    nativeClaudeSessionStatus: "unavailable",
    title: buildCodexSessionTitle(cwd, rolloutId, userPrompt),
    cwd,
    project: path.basename(cwd) || null,
    agent: "codex",
    provider: "codex",
    model: readNonEmptyString(scanned.sessionMeta.model) || readNonEmptyString(scanned.sessionMeta.model_slug),
    launchProfileName: null,
    launchProfileFingerprint: null,
    authSecretRef: null,
    tmuxPaneId: null,
    tmuxSessionName: null,
    pid: null,
    status: "idle",
    createdAt,
    lastActivityAt,
    lastPreviewText: null,
    hidden: false,
    transcriptCacheState: scanned.messageCount > 0 ? "fresh" : "empty",
    metadata: compactObject({
      source: TRANSCRIPT_SOURCE_CODEX_ROLLOUT,
      rolloutPathHash: pathHash,
      rolloutFileName: limitText(candidate.fileName, 96),
      rolloutIdShort: rolloutId.slice(0, 12),
      originator: limitText(readNonEmptyString(scanned.sessionMeta.originator), 64),
      cliSource: limitText(readNonEmptyString(scanned.sessionMeta.source), 32),
      fileMtime: candidate.mtime,
      fileBytes: String(candidate.size),
      recordsScanned: String(scanned.recordsScanned),
      messageCount: String(scanned.messageCount),
      lastTranscriptAt: scanned.lastTimestamp,
      fileMtimeAt: candidate.mtime,
      lastActivitySource,
      userMessageCount: String(scanned.userMessageCount),
      assistantMessageCount: String(scanned.assistantMessageCount),
      reasoningMessageCount: String(scanned.reasoningMessageCount),
      toolMessageCount: String(scanned.toolMessageCount),
      skippedRecordCount: String(scanned.skippedRecordCount),
      bootstrapSkippedCount: String(scanned.bootstrapSkippedCount || 0),
      firstTimestamp: scanned.firstTimestamp,
      lastTimestamp: scanned.lastTimestamp,
    }),
  };
}

function findRolloutFileForSession(session, options = {}) {
  const metadata = session?.metadata || {};
  const expectedPathHash = readNonEmptyString(metadata.rolloutPathHash);
  if (!expectedPathHash) {
    return null;
  }

  const fsImpl = options.fsImpl || fs;
  for (const root of resolveCodexSessionsRoots(options)) {
    const match = collectRolloutFileCandidates(root, { fsImpl })
      .find((candidate) => digestText(normalizeRolloutIdentityPath(candidate.filePath, fsImpl)) === expectedPathHash);
    if (match) {
      return match;
    }
  }
  return null;
}

function parseCodexRolloutJsonl(jsonlText, options = {}) {
  const state = {
    assistantMessageCount: 0,
    bootstrapSkippedCount: 0,
    firstRealUserPrompt: null,
    firstTimestamp: null,
    lastTimestamp: null,
    lastTimestampMs: null,
    latestRealUserPrompt: null,
    messageCount: 0,
    reasoningMessageCount: 0,
    recordsScanned: 0,
    sessionMeta: null,
    skippedRecordCount: 0,
    toolMessageCount: 0,
    userMessageCount: 0,
  };
  const messages = [];
  const commandCalls = new Map();

  for (const line of String(jsonlText || "").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }

    let entry;
    try {
      entry = JSON.parse(trimmed);
    } catch {
      state.skippedRecordCount += 1;
      continue;
    }

    if (!isPlainObject(entry)) {
      state.skippedRecordCount += 1;
      continue;
    }
    state.recordsScanned += 1;
    noteTimestamp(state, entry.timestamp || entry.created_at || entry.createdAt);

    if (entry.type === "session_meta") {
      state.sessionMeta = normalizeSessionMeta(entry.payload || entry);
      continue;
    }

    const normalized = normalizeCodexRolloutMessage(entry, {
      commandCalls,
      fallbackSessionId: options.fallbackSessionId,
      includeDetail: options.detail === true,
    });
    if (!normalized) {
      state.skippedRecordCount += 1;
      continue;
    }

    // Check if this is a user message with bootstrap context text
    if (normalized.role === "user" && normalized._bootstrapContext === true) {
      state.bootstrapSkippedCount += 1;
      // Still track user prompt for title generation only if it's NOT bootstrap
      // (bootstrap messages already have _bootstrapContext set, so they won't be tracked)
      continue;
    }

    state.messageCount += 1;
    if (normalized.role === "user") {
      state.userMessageCount += 1;
      // Track real user prompts for title generation
      const userText = extractMessageText(normalized);
      if (userText && !isBootstrapContextText(userText)) {
        if (!state.firstRealUserPrompt) {
          state.firstRealUserPrompt = userText;
        }
        state.latestRealUserPrompt = userText;
      }
    } else if (normalized.role === "assistant") {
      state.assistantMessageCount += 1;
    } else if (normalized.role === "reasoning") {
      state.reasoningMessageCount += 1;
    } else if (normalized.role === "tool") {
      state.toolMessageCount += 1;
    }

    if (options.detail === true && messages.length < MAX_DETAIL_MESSAGES) {
      messages.push(normalized);
    }
  }

  const { lastTimestampMs: _lastTimestampMs, ...publicState } = state;
  return {
    ...publicState,
    transcript: buildCodexTranscriptSnapshot({
      messages,
      nativePathState: state.recordsScanned > 0 ? NATIVE_PATH_STATE_CONFIRMED : NATIVE_PATH_STATE_UNAVAILABLE,
    }),
  };
}

function normalizeCodexRolloutMessage(entry, { commandCalls, fallbackSessionId, includeDetail }) {
  if (entry.type === "event_msg") {
    return normalizeCodexEventMessage(entry, { fallbackSessionId });
  }
  if (entry.type !== "response_item") {
    return null;
  }

  const payload = isPlainObject(entry.payload) ? entry.payload : {};
  const itemType = normalizeRolloutItemType(payload.type);
  if (itemType === "reasoning") {
    const reasoningText = extractReasoningText(payload);
    // Only show reasoning when there is non-placeholder text
    if (!reasoningText || isPlaceholderReasoning(reasoningText)) {
      return null;
    }
    return buildMessage({
      entry,
      role: "reasoning",
      fallbackSessionId,
      content: [{ kind: "thinking", type: "thinking", text: reasoningText }],
    });
  }

  if (itemType === "message") {
    const role = readNonEmptyString(payload.role) || "assistant";
    // Hide system/developer context messages before they enter chat, counts, or titles
    if (role === "system" || role === "developer") {
      return null;
    }
    const text = flattenContentText(payload.content) || readNonEmptyString(payload.text);
    if (!text) return null;
    // Mark bootstrap context user messages so they can be filtered
    if (role === "user" && isBootstrapContextText(text)) {
      const msg = buildMessage({ entry, role: "user", fallbackSessionId, content: [makeTextContent("text", text)] });
      msg._bootstrapContext = true;
      return msg;
    }
    return buildMessage({ entry, role, fallbackSessionId, content: [makeTextContent("text", text)] });
  }

  if (itemType === "functioncall") {
    const callId = readNonEmptyString(payload.call_id) || readNonEmptyString(payload.callId) || readNonEmptyString(payload.id);
    const toolName = readNonEmptyString(payload.name);
    if (!callId || !toolName) {
      return null;
    }
    const parsedArguments = parseToolArguments(payload.arguments);
    commandCalls.set(callId, {
      command: resolveToolCommand(toolName, parsedArguments),
      cwd: readNonEmptyString(parsedArguments.workdir) || readNonEmptyString(parsedArguments.cwd),
      toolName,
    });
    return buildMessage({
      entry,
      role: "tool",
      fallbackSessionId,
      content: [{
        kind: "tool_use",
        type: "tool_use",
        id: callId,
        name: toolName,
        inputPreviewText: includeDetail ? previewJsonValue(parsedArguments, MAX_TOOL_PREVIEW_LENGTH) : null,
      }],
    });
  }

  if (itemType === "functioncalloutput") {
    const callId = readNonEmptyString(payload.call_id) || readNonEmptyString(payload.callId) || readNonEmptyString(payload.id);
    const toolCall = commandCalls.get(callId) || {};
    const output = readNonEmptyString(payload.output) || flattenContentText(payload.content);
    if (!callId || !output) {
      return null;
    }
    commandCalls.delete(callId);
    return buildMessage({
      entry,
      role: "tool",
      fallbackSessionId,
      content: [{
        kind: "tool_result",
        type: "tool_result",
        toolUseId: callId,
        command: toolCall.command || null,
        cwd: toolCall.cwd || null,
        isError: payload.is_error === true || payload.isError === true,
        text: output,
      }],
    });
  }

  return null;
}

function normalizeCodexEventMessage(entry, { fallbackSessionId }) {
  const payload = isPlainObject(entry.payload) ? entry.payload : {};
  const eventType = readNonEmptyString(payload.type);
  if (eventType === "user_message") {
    const text = readNonEmptyString(payload.message) || readNonEmptyString(payload.text);
    if (!text) return null;
    // Mark bootstrap context user messages so they can be filtered
    if (isBootstrapContextText(text)) {
      const msg = buildMessage({ entry, role: "user", fallbackSessionId, content: [makeTextContent("text", text)] });
      msg._bootstrapContext = true;
      return msg;
    }
    return buildMessage({ entry, role: "user", fallbackSessionId, content: [makeTextContent("text", text)] });
  }
  if (eventType === "agent_reasoning") {
    const text = readNonEmptyString(payload.message) || readNonEmptyString(payload.text) || readNonEmptyString(payload.summary);
    // Only show reasoning when there is non-placeholder text
    if (!text || isPlaceholderReasoning(text)) return null;
    return buildMessage({ entry, role: "reasoning", fallbackSessionId, content: [makeTextContent("thinking", text)] });
  }
  if (eventType === "agent_message") {
    const text = readNonEmptyString(payload.message) || readNonEmptyString(payload.text);
    return text ? buildMessage({ entry, role: "assistant", fallbackSessionId, content: [makeTextContent("text", text)] }) : null;
  }
  return null;
}

function extractMessageText(message) {
  if (!message || !Array.isArray(message.content)) return null;
  for (const item of message.content) {
    const text = readNonEmptyString(item.text);
    if (text) return text;
  }
  return null;
}

function buildMessage({ entry, role, fallbackSessionId, content }) {
  const timestamp = normalizeTimestamp(entry.timestamp || entry.created_at || entry.createdAt);
  const id = readNonEmptyString(entry.id)
    || readNonEmptyString(entry.item_id)
    || readNonEmptyString(entry.payload?.id)
    || digestText(JSON.stringify({ role, timestamp, content })).slice(0, 16);

  return {
    id,
    sessionId: fallbackSessionId || "codex-rollout",
    uuid: id,
    parentUuid: readNullableString(entry.parent_id || entry.parentId),
    timestamp,
    createdAt: timestamp,
    type: TRANSCRIPT_SOURCE_CODEX_ROLLOUT,
    role,
    content: content.map((item) => sanitizeContentItem(item)).filter(Boolean),
  };
}

function buildCodexTranscriptSnapshot({ messages = [], nativePathState = NATIVE_PATH_STATE_UNAVAILABLE } = {}) {
  return {
    source: TRANSCRIPT_SOURCE_CODEX_ROLLOUT,
    nativePathState,
    messages,
    rawPreviewText: null,
  };
}

function normalizeSessionMeta(value) {
  const meta = isPlainObject(value) ? value : {};
  return compactObject({
    id: readNonEmptyString(meta.id) || readNonEmptyString(meta.session_id) || readNonEmptyString(meta.sessionId),
    cwd: readNonEmptyString(meta.cwd) || readNonEmptyString(meta.working_directory) || readNonEmptyString(meta.workdir),
    model: readNonEmptyString(meta.model) || readNonEmptyString(meta.model_slug) || readNonEmptyString(meta.modelSlug),
    model_slug: readNonEmptyString(meta.model_slug) || readNonEmptyString(meta.modelSlug),
    originator: readNonEmptyString(meta.originator),
    source: readNonEmptyString(meta.source),
  });
}

function isCodexCliRolloutOrigin(sessionMeta) {
  const originator = normalizeIdentifier(sessionMeta?.originator);
  const source = normalizeIdentifier(sessionMeta?.source);
  if (!originator && !source) {
    return false;
  }
  if (originator.includes("mobile") || originator.includes("ios") || source.includes("mobile") || source.includes("ios")) {
    return false;
  }
  return source === "cli" && (
    originator === "codextui"
      || originator === "codexclirs"
      || originator === "codexcli"
      || originator.startsWith("codex")
  );
}

function buildCodexSessionTitle(cwd, rolloutId, userPrompt) {
  const project = path.basename(cwd || "") || "Codex";
  // When we have a real user prompt, build meaningful title: "project - userPrompt"
  if (userPrompt) {
    const truncated = userPrompt.length > 60 ? userPrompt.slice(0, 57) + "..." : userPrompt;
    return limitText(`${project} - ${truncated}`, MAX_DISCOVERY_TITLE_LENGTH);
  }
  // Fall back to rollout ID only (no "Codex rollout" prefix since it is already shown as provider)
  const idShort = String(rolloutId || "").slice(0, 8);
  return limitText(`${project} - ${idShort}`, MAX_DISCOVERY_TITLE_LENGTH);
}

function noteTimestamp(state, value) {
  const parsed = parseValidTimestamp(value);
  if (!parsed) {
    return;
  }
  if (!state.firstTimestamp) {
    state.firstTimestamp = parsed.iso;
  }
  if (state.lastTimestampMs === null || parsed.ms > state.lastTimestampMs) {
    state.lastTimestampMs = parsed.ms;
    state.lastTimestamp = parsed.iso;
  }
}

function normalizeRolloutItemType(value) {
  return String(value || "").replace(/[^A-Za-z0-9]/g, "").toLowerCase();
}

function extractReasoningText(payload) {
  if (Array.isArray(payload?.summary)) {
    const summary = payload.summary
      .map((part) => readNonEmptyString(part?.text) || readNonEmptyString(part?.summary))
      .filter(Boolean)
      .join("\n");
    if (summary) {
      return summary;
    }
  }
  return readNonEmptyString(payload?.text) || readNonEmptyString(payload?.content);
}

function parseToolArguments(rawArguments) {
  if (isPlainObject(rawArguments)) {
    return rawArguments;
  }
  if (typeof rawArguments !== "string") {
    return {};
  }
  try {
    const parsed = JSON.parse(rawArguments);
    return isPlainObject(parsed) ? parsed : {};
  } catch {
    return {};
  }
}

function resolveToolCommand(toolName, argumentsObject) {
  const normalized = normalizeIdentifier(toolName);
  if (normalized !== "execcommand" && normalized !== "shellcommand") {
    return toolName;
  }
  return readNonEmptyString(argumentsObject.cmd)
    || readNonEmptyString(argumentsObject.command)
    || readNonEmptyString(argumentsObject.raw_command)
    || readNonEmptyString(argumentsObject.rawCommand)
    || toolName;
}

function makeTextContent(kind, text) {
  return {
    kind,
    type: kind,
    text,
  };
}

function sanitizeContentItem(value) {
  if (!isPlainObject(value)) {
    return null;
  }
  const kind = readNonEmptyString(value.kind) || readNonEmptyString(value.type);
  if (kind === "text" || kind === "thinking") {
    const text = readNullableString(value.text, MAX_TEXT_LENGTH);
    return text ? { kind, type: kind, text } : null;
  }
  if (kind === "tool_use") {
    return compactObject({
      kind,
      type: kind,
      id: readNullableString(value.id),
      name: readNullableString(value.name),
      inputPreviewText: readNullableString(value.inputPreviewText, MAX_TOOL_PREVIEW_LENGTH),
    });
  }
  if (kind === "tool_result") {
    return compactObject({
      kind,
      type: kind,
      toolUseId: readNullableString(value.toolUseId),
      command: readNullableString(value.command, MAX_TOOL_PREVIEW_LENGTH),
      cwd: readNullableString(value.cwd, MAX_TOOL_PREVIEW_LENGTH),
      isError: value.isError === true,
      text: readNullableString(value.text, MAX_TEXT_LENGTH),
    });
  }
  return null;
}

function flattenContentText(value) {
  if (typeof value === "string") {
    return limitText(value, MAX_TEXT_LENGTH);
  }
  if (Array.isArray(value)) {
    const pieces = value.flatMap((entry) => flattenContentText(entry) || []);
    return pieces.length > 0 ? limitText(pieces.join("\n"), MAX_TEXT_LENGTH) : null;
  }
  if (!isPlainObject(value)) {
    return null;
  }
  return readNullableString(value.text, MAX_TEXT_LENGTH)
    || readNullableString(value.content, MAX_TEXT_LENGTH)
    || flattenContentText(value.content);
}

function previewJsonValue(value, maxLength) {
  try {
    return limitText(JSON.stringify(value), maxLength);
  } catch {
    return null;
  }
}

function readBoundedTextFile(fsImpl, filePath, maxBytes = Number.POSITIVE_INFINITY) {
  const buffer = fsImpl.readFileSync(filePath);
  if (!Number.isFinite(maxBytes) || buffer.length <= maxBytes) {
    return buffer.toString("utf8");
  }
  return buffer.subarray(0, maxBytes).toString("utf8");
}

function compareRolloutCandidates(left, right) {
  return right.mtimeMs - left.mtimeMs || left.filePath.localeCompare(right.filePath);
}

function toStatTime(stat) {
  if (Number.isFinite(stat?.mtimeMs)) {
    return stat.mtimeMs;
  }
  if (stat?.mtime instanceof Date) {
    return stat.mtime.getTime();
  }
  return 0;
}

function safeReadDirents(fsImpl, dirPath) {
  try {
    return fsImpl.readdirSync(dirPath, { withFileTypes: true });
  } catch {
    return [];
  }
}

function safeStatSync(fsImpl, filePath) {
  try {
    return fsImpl.statSync(filePath);
  } catch {
    return null;
  }
}

function safeExistsSync(fsImpl, filePath) {
  try {
    return fsImpl.existsSync(filePath);
  } catch {
    return false;
  }
}

function digestText(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

function normalizeTimestamp(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date(value).toISOString();
  }
  const candidate = readNonEmptyString(value);
  if (!candidate) {
    return null;
  }
  const timestamp = Date.parse(candidate);
  return Number.isNaN(timestamp) ? candidate : new Date(timestamp).toISOString();
}

function parseValidTimestamp(value) {
  const normalized = normalizeTimestamp(value);
  if (!normalized) {
    return null;
  }
  const ms = Date.parse(normalized);
  if (Number.isNaN(ms)) {
    return null;
  }
  return { iso: new Date(ms).toISOString(), ms };
}

function readPositiveInteger(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.trunc(value));
  }
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? Math.max(0, parsed) : null;
  }
  return null;
}

function normalizeIdentifier(value) {
  return String(value || "").replace(/[^A-Za-z0-9]/g, "").toLowerCase();
}

function readNonEmptyString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function readNullableString(value, maxLength = Number.POSITIVE_INFINITY) {
  if (typeof value !== "string") {
    return null;
  }
  return limitText(value, maxLength);
}

function limitText(value, maxLength) {
  const normalized = typeof value === "string" ? value : null;
  if (!normalized) {
    return null;
  }
  if (!Number.isFinite(maxLength) || normalized.length <= maxLength) {
    return normalized;
  }
  return normalized.slice(0, maxLength);
}

function compactObject(value) {
  return Object.fromEntries(Object.entries(value).filter(([, entry]) => entry !== null && entry !== undefined));
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

module.exports = {
  TRANSCRIPT_SOURCE_CODEX_ROLLOUT,
  discoverCodexRolloutSessions,
  isBootstrapContextText,
  isCodexCliRolloutOrigin,
  isCodexRolloutSession,
  isPlaceholderReasoning,
  parseCodexRolloutJsonl,
  readCodexRolloutTranscriptSnapshot,
  resolveCodexSessionsRoots,
};
