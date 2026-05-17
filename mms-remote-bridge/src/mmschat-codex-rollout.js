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

function discoverCodexRolloutSessions(options = {}) {
  const fsImpl = options.fsImpl || fs;
  const maxFiles = readPositiveInteger(options.maxFiles) || MAX_DISCOVERY_FILES;
  const maxFileBytes = readPositiveInteger(options.maxFileBytes) || MAX_DISCOVERY_FILE_BYTES;
  const roots = resolveCodexSessionsRoots(options);

  return roots
    .flatMap((root) => collectRolloutFileCandidates(root, { fsImpl }))
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
  if (explicitCodexHome) {
    return [path.join(path.resolve(explicitCodexHome), "sessions")];
  }

  return [path.join(osImpl.homedir(), ".codex", "sessions")];
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

  const rolloutId = readNonEmptyString(scanned.sessionMeta.id) || digestText(candidate.filePath).slice(0, 16);
  const cwd = readNonEmptyString(scanned.sessionMeta.cwd) || "~";
  const lastActivityAt = scanned.lastTimestamp || candidate.mtime;
  const createdAt = scanned.firstTimestamp || lastActivityAt;
  const pathHash = digestText(candidate.filePath);

  return {
    mmschatId: `mmschat_codex_${pathHash.slice(0, 24)}`,
    nativeClaudeSessionId: null,
    nativeClaudeSessionStatus: "unavailable",
    title: buildCodexSessionTitle(cwd, rolloutId),
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
      userMessageCount: String(scanned.userMessageCount),
      assistantMessageCount: String(scanned.assistantMessageCount),
      reasoningMessageCount: String(scanned.reasoningMessageCount),
      toolMessageCount: String(scanned.toolMessageCount),
      skippedRecordCount: String(scanned.skippedRecordCount),
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
      .find((candidate) => digestText(candidate.filePath) === expectedPathHash);
    if (match) {
      return match;
    }
  }
  return null;
}

function parseCodexRolloutJsonl(jsonlText, options = {}) {
  const state = {
    assistantMessageCount: 0,
    firstTimestamp: null,
    lastTimestamp: null,
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

    state.messageCount += 1;
    if (normalized.role === "user") {
      state.userMessageCount += 1;
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

  return {
    ...state,
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
    return buildMessage({
      entry,
      role: "reasoning",
      fallbackSessionId,
      content: [{ kind: "thinking", type: "thinking", text: extractReasoningText(payload) || "Thinking..." }],
    });
  }

  if (itemType === "message") {
    const role = readNonEmptyString(payload.role) || "assistant";
    const text = flattenContentText(payload.content) || readNonEmptyString(payload.text);
    return text ? buildMessage({ entry, role, fallbackSessionId, content: [makeTextContent("text", text)] }) : null;
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
    return text ? buildMessage({ entry, role: "user", fallbackSessionId, content: [makeTextContent("text", text)] }) : null;
  }
  if (eventType === "agent_reasoning") {
    const text = readNonEmptyString(payload.message) || readNonEmptyString(payload.text) || readNonEmptyString(payload.summary);
    return text ? buildMessage({ entry, role: "reasoning", fallbackSessionId, content: [makeTextContent("thinking", text)] }) : null;
  }
  if (eventType === "agent_message") {
    const text = readNonEmptyString(payload.message) || readNonEmptyString(payload.text);
    return text ? buildMessage({ entry, role: "assistant", fallbackSessionId, content: [makeTextContent("text", text)] }) : null;
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

function buildCodexSessionTitle(cwd, rolloutId) {
  const project = path.basename(cwd || "") || "Codex";
  return limitText(`${project} - Codex rollout ${String(rolloutId || "").slice(0, 8)}`, MAX_DISCOVERY_TITLE_LENGTH);
}

function noteTimestamp(state, value) {
  const timestamp = normalizeTimestamp(value);
  if (!timestamp) {
    return;
  }
  if (!state.firstTimestamp) {
    state.firstTimestamp = timestamp;
  }
  state.lastTimestamp = timestamp;
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
  isCodexCliRolloutOrigin,
  isCodexRolloutSession,
  parseCodexRolloutJsonl,
  readCodexRolloutTranscriptSnapshot,
  resolveCodexSessionsRoots,
};
