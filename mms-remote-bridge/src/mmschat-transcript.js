// FILE: mmschat-transcript.js
// Purpose: Resolves Claude native project JSONL transcripts and persists sanitized MMSChat cache snapshots.
// Layer: Transcript helper
// Exports: Native path resolution, JSONL parsing, transcript snapshot, and cache helpers for MMSChat detail reads.
// Depends on: crypto, fs, os, path, ./mmschat-store

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  buildAtomicTempPath,
  resolveMMSChatStateDir,
} = require("./mmschat-store");

const CLAUDE_HOME_DIRNAME = ".claude";
const CLAUDE_PROJECTS_DIRNAME = "projects";
const MMSCHAT_TRANSCRIPT_CACHE_DIRNAME = "mmschat-transcripts";
const MMSCHAT_TRANSCRIPT_CACHE_VERSION = 1;
const TRANSCRIPT_SOURCE_NATIVE_JSONL = "native-jsonl";
const TRANSCRIPT_SOURCE_RAW_FALLBACK = "raw-fallback";
const NATIVE_PATH_STATE_CONFIRMED = "confirmed";
const NATIVE_PATH_STATE_UNAVAILABLE = "unavailable";
const MAX_TEXT_LENGTH = 12_000;
const MAX_TOOL_PREVIEW_LENGTH = 4_000;

function resolveClaudeHomeDir(options = {}) {
  if (isNonEmptyString(options.claudeHome)) {
    return path.resolve(options.claudeHome);
  }

  const osImpl = options.osImpl || os;
  return path.join(osImpl.homedir(), CLAUDE_HOME_DIRNAME);
}

function resolveClaudeProjectsDir(options = {}) {
  if (isNonEmptyString(options.projectsRoot)) {
    return path.resolve(options.projectsRoot);
  }

  return path.join(resolveClaudeHomeDir(options), CLAUDE_PROJECTS_DIRNAME);
}

function buildClaudeProjectKey(cwd) {
  const normalizedCwd = normalizeCwd(cwd);
  if (!normalizedCwd) {
    return null;
  }

  return normalizedCwd.replace(/[\\/:]+/g, "-");
}

function buildClaudeProjectKeyCandidates(cwd) {
  const normalizedCwd = normalizeCwd(cwd);
  if (!normalizedCwd) {
    return [];
  }

  const candidates = [
    normalizedCwd,
    path.resolve(normalizedCwd),
    normalizedCwd.replace(/\s+/g, " "),
  ].filter(Boolean);

  return uniqueStrings(candidates.map((value) => buildClaudeProjectKey(value)).concat([
    buildClaudeProjectKey(normalizedCwd.replace(/\s+/g, "-")),
  ]));
}

function resolveNativeClaudeProjectJsonlPath(options = {}) {
  const nativeClaudeSessionId = readNonEmptyString(options.nativeClaudeSessionId);
  const cwd = normalizeCwd(options.cwd);
  const projectsRoot = resolveClaudeProjectsDir(options);
  const fsImpl = options.fsImpl || fs;

  if (!nativeClaudeSessionId || !cwd) {
    return buildUnavailableResolution({
      nativeClaudeSessionId,
      cwd,
      projectsRoot,
      reason: "missing-session-or-cwd",
    });
  }

  const candidateKeys = Array.isArray(options.projectKeys)
    ? uniqueStrings(options.projectKeys.map((value) => readNonEmptyString(value)))
    : buildClaudeProjectKeyCandidates(cwd);

  for (const projectKey of candidateKeys) {
    const nativePath = path.join(projectsRoot, projectKey, `${nativeClaudeSessionId}.jsonl`);
    if (safeExistsSync(fsImpl, nativePath)) {
      return {
        nativePathState: NATIVE_PATH_STATE_CONFIRMED,
        nativeClaudeSessionId,
        cwd,
        projectsRoot,
        projectKey,
        nativePath,
        resolvedBy: "cwd-key",
      };
    }
  }

  const scannedPath = scanProjectsRootForSession(nativeClaudeSessionId, projectsRoot, fsImpl);
  if (scannedPath) {
    return {
      nativePathState: NATIVE_PATH_STATE_CONFIRMED,
      nativeClaudeSessionId,
      cwd,
      projectsRoot,
      projectKey: path.basename(path.dirname(scannedPath)),
      nativePath: scannedPath,
      resolvedBy: "projects-scan",
    };
  }

  return buildUnavailableResolution({
    nativeClaudeSessionId,
    cwd,
    projectsRoot,
    reason: "native-jsonl-not-found",
  });
}

function parseClaudeNativeJsonl(jsonlText, options = {}) {
  if (!isNonEmptyString(jsonlText)) {
    return [];
  }

  const expectedSessionId = readNonEmptyString(options.nativeClaudeSessionId);
  const records = [];
  const lines = jsonlText.split(/\r?\n/);

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index].trim();
    if (!line) {
      continue;
    }

    let parsed;
    try {
      parsed = JSON.parse(line);
    } catch (error) {
      throw new Error(`Invalid Claude JSONL line ${index + 1}: ${error.message}`);
    }

    const record = normalizeNativeTranscriptRecord(parsed, { expectedSessionId });
    if (record) {
      records.push(record);
    }
  }

  if (expectedSessionId && !records.some((record) => record.sessionId === expectedSessionId)) {
    throw new Error(`Native JSONL did not contain sessionId ${expectedSessionId}.`);
  }

  return records;
}

function readClaudeNativeJsonlFile(options = {}) {
  const nativePath = readNonEmptyString(options.nativePath);
  const fsImpl = options.fsImpl || fs;

  if (!nativePath || !safeExistsSync(fsImpl, nativePath)) {
    throw new Error("Native Claude JSONL file is unavailable.");
  }

  const jsonlText = fsImpl.readFileSync(nativePath, "utf8");
  return parseClaudeNativeJsonl(jsonlText, options);
}

function readNativeClaudeTranscriptSnapshot(options = {}) {
  const resolution = resolveNativeClaudeProjectJsonlPath(options);
  if (resolution.nativePathState !== NATIVE_PATH_STATE_CONFIRMED) {
    return buildRawFallbackTranscriptSnapshot(options.rawPreviewText);
  }

  try {
    const messages = readClaudeNativeJsonlFile({
      ...options,
      nativePath: resolution.nativePath,
      nativeClaudeSessionId: resolution.nativeClaudeSessionId,
    });
    return buildTranscriptSnapshot({
      source: TRANSCRIPT_SOURCE_NATIVE_JSONL,
      nativePathState: NATIVE_PATH_STATE_CONFIRMED,
      messages,
      rawPreviewText: null,
    });
  } catch {
    return buildRawFallbackTranscriptSnapshot(options.rawPreviewText);
  }
}

function buildTranscriptSnapshot(snapshot = {}) {
  return {
    source: snapshot.source === TRANSCRIPT_SOURCE_NATIVE_JSONL
      ? TRANSCRIPT_SOURCE_NATIVE_JSONL
      : TRANSCRIPT_SOURCE_RAW_FALLBACK,
    nativePathState: snapshot.nativePathState === NATIVE_PATH_STATE_CONFIRMED
      ? NATIVE_PATH_STATE_CONFIRMED
      : NATIVE_PATH_STATE_UNAVAILABLE,
    messages: Array.isArray(snapshot.messages)
      ? snapshot.messages.map((message) => sanitizeSnapshotMessage(message)).filter(Boolean)
      : [],
    rawPreviewText: readNullableString(snapshot.rawPreviewText, MAX_TEXT_LENGTH),
  };
}

function buildRawFallbackTranscriptSnapshot(rawPreviewText) {
  return buildTranscriptSnapshot({
    source: TRANSCRIPT_SOURCE_RAW_FALLBACK,
    nativePathState: NATIVE_PATH_STATE_UNAVAILABLE,
    messages: [],
    rawPreviewText,
  });
}

function resolveMMSChatTranscriptCacheDir(options = {}) {
  return path.join(resolveMMSChatStateDir(options), MMSCHAT_TRANSCRIPT_CACHE_DIRNAME);
}

function resolveMMSChatTranscriptCachePath(options = {}) {
  const explicitCacheKey = readNonEmptyString(options.cacheKey);
  const cacheKey = explicitCacheKey
    ? sanitizePathSegment(explicitCacheKey)
    : buildTranscriptCacheKey(options);

  if (!cacheKey) {
    throw new Error("A transcript cache key requires mmschatId, nativeClaudeSessionId, cwd, or cacheKey.");
  }

  return path.join(resolveMMSChatTranscriptCacheDir(options), `${cacheKey}.json`);
}

function readMMSChatTranscriptCache(options = {}) {
  const filePath = resolveMMSChatTranscriptCachePath(options);
  const fsImpl = options.fsImpl || fs;

  if (!safeExistsSync(fsImpl, filePath)) {
    return null;
  }

  try {
    const parsed = JSON.parse(fsImpl.readFileSync(filePath, "utf8"));
    const transcript = buildTranscriptSnapshot(parsed?.transcript || {});
    return {
      version: MMSCHAT_TRANSCRIPT_CACHE_VERSION,
      cachedAt: readNullableString(parsed?.cachedAt),
      transcript,
    };
  } catch {
    return null;
  }
}

function writeMMSChatTranscriptCache(snapshot, options = {}) {
  const filePath = resolveMMSChatTranscriptCachePath(options);
  const fsImpl = options.fsImpl || fs;
  const now = options.now || (() => Date.now());
  const random = options.random || Math.random;
  const payload = {
    version: MMSCHAT_TRANSCRIPT_CACHE_VERSION,
    cachedAt: new Date(now()).toISOString(),
    transcript: buildTranscriptSnapshot(snapshot),
  };
  const serialized = `${JSON.stringify(payload, null, 2)}\n`;
  const tempPath = buildAtomicTempPath(filePath, { now, random });

  fsImpl.mkdirSync(path.dirname(filePath), { recursive: true });

  try {
    fsImpl.writeFileSync(tempPath, serialized, { mode: 0o600 });
    setBestEffortFileMode(tempPath, fsImpl);
    fsImpl.renameSync(tempPath, filePath);
    setBestEffortFileMode(filePath, fsImpl);
  } catch (error) {
    try {
      fsImpl.rmSync(tempPath, { force: true });
    } catch {
      // Ignore best-effort cleanup for failed cache writes.
    }
    throw error;
  }

  return payload;
}

function normalizeNativeTranscriptRecord(value, { expectedSessionId } = {}) {
  if (!isPlainObject(value) || !isPlainObject(value.message)) {
    return null;
  }

  const sessionId = readNonEmptyString(value.sessionId);
  if (!sessionId) {
    return null;
  }

  if (expectedSessionId && sessionId !== expectedSessionId) {
    return null;
  }

  const role = readNonEmptyString(value.message.role);
  if (!role) {
    return null;
  }

  return {
    sessionId,
    uuid: readNullableString(value.uuid),
    parentUuid: readNullableString(value.parentUuid),
    timestamp: normalizeTimestamp(value.timestamp),
    type: readNullableString(value.type),
    role,
    content: normalizeMessageContent(value.message.content),
  };
}

function sanitizeSnapshotMessage(value) {
  if (!isPlainObject(value) || !isNonEmptyString(value.sessionId) || !isNonEmptyString(value.role)) {
    return null;
  }

  return {
    sessionId: value.sessionId,
    uuid: readNullableString(value.uuid),
    parentUuid: readNullableString(value.parentUuid),
    timestamp: normalizeTimestamp(value.timestamp),
    type: readNullableString(value.type),
    role: value.role,
    content: Array.isArray(value.content)
      ? value.content.map((item) => sanitizeContentItem(item)).filter(Boolean)
      : [],
  };
}

function normalizeMessageContent(content) {
  const normalized = normalizeContentItems(content);
  return normalized.map((item) => sanitizeContentItem(item)).filter(Boolean);
}

function normalizeContentItems(content) {
  if (typeof content === "string") {
    return [makeTextItem("text", content)];
  }

  if (Array.isArray(content)) {
    return content.flatMap((item) => normalizeContentItems(item));
  }

  if (!isPlainObject(content)) {
    return [];
  }

  const itemType = readNonEmptyString(content.type);
  if (itemType === "text") {
    return [makeTextItem("text", content.text)];
  }

  if (itemType === "thinking") {
    return [makeTextItem("thinking", content.thinking || content.text)];
  }

  if (itemType === "tool_use") {
    return [
      {
        kind: "tool_use",
        id: readNullableString(content.id),
        name: readNullableString(content.name),
        inputPreviewText: previewJsonValue(content.input, MAX_TOOL_PREVIEW_LENGTH),
      },
    ];
  }

  if (itemType === "tool_result") {
    return [
      {
        kind: "tool_result",
        toolUseId: readNullableString(content.tool_use_id || content.toolUseId || content.id),
        isError: content.is_error === true || content.isError === true,
        text: flattenContentText(content.content),
      },
    ];
  }

  if (Object.prototype.hasOwnProperty.call(content, "content")) {
    return normalizeContentItems(content.content);
  }

  return [];
}

function sanitizeContentItem(value) {
  if (!isPlainObject(value) || !isNonEmptyString(value.kind)) {
    return null;
  }

  if (value.kind === "text" || value.kind === "thinking") {
    const text = readNullableString(value.text, MAX_TEXT_LENGTH);
    if (!text) {
      return null;
    }
    return {
      kind: value.kind,
      text,
    };
  }

  if (value.kind === "tool_use") {
    return {
      kind: "tool_use",
      id: readNullableString(value.id),
      name: readNullableString(value.name),
      inputPreviewText: readNullableString(value.inputPreviewText, MAX_TOOL_PREVIEW_LENGTH),
    };
  }

  if (value.kind === "tool_result") {
    return {
      kind: "tool_result",
      toolUseId: readNullableString(value.toolUseId),
      isError: value.isError === true,
      text: readNullableString(value.text, MAX_TEXT_LENGTH),
    };
  }

  return null;
}

function makeTextItem(kind, text) {
  return {
    kind,
    text: readNullableString(text, MAX_TEXT_LENGTH),
  };
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

  if (typeof value.text === "string") {
    return limitText(value.text, MAX_TEXT_LENGTH);
  }

  if (typeof value.content === "string") {
    return limitText(value.content, MAX_TEXT_LENGTH);
  }

  if (Array.isArray(value.content)) {
    return flattenContentText(value.content);
  }

  return null;
}

function normalizeTimestamp(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date(value).toISOString();
  }

  return readNullableString(value);
}

function previewJsonValue(value, maxLength) {
  if (typeof value === "string") {
    return limitText(value, maxLength);
  }

  if (value === null || value === undefined) {
    return null;
  }

  if (typeof value === "number" || typeof value === "boolean") {
    return String(value);
  }

  try {
    return limitText(JSON.stringify(value), maxLength);
  } catch {
    return null;
  }
}

function buildTranscriptCacheKey(options = {}) {
  const mmschatId = readNonEmptyString(options.mmschatId);
  if (mmschatId) {
    return `mmschat-${sanitizePathSegment(mmschatId)}`;
  }

  const nativeClaudeSessionId = readNonEmptyString(options.nativeClaudeSessionId);
  if (nativeClaudeSessionId) {
    return `native-${sanitizePathSegment(nativeClaudeSessionId)}`;
  }

  const cwd = normalizeCwd(options.cwd);
  if (cwd) {
    return `cwd-${digestText(cwd).slice(0, 16)}`;
  }

  return null;
}

function scanProjectsRootForSession(nativeClaudeSessionId, projectsRoot, fsImpl) {
  if (!nativeClaudeSessionId || !safeExistsSync(fsImpl, projectsRoot)) {
    return null;
  }

  let entries;
  try {
    entries = fsImpl.readdirSync(projectsRoot, { withFileTypes: true });
  } catch {
    return null;
  }

  for (const entry of entries) {
    if (!entry?.isDirectory?.()) {
      continue;
    }

    const nativePath = path.join(projectsRoot, entry.name, `${nativeClaudeSessionId}.jsonl`);
    if (safeExistsSync(fsImpl, nativePath)) {
      return nativePath;
    }
  }

  return null;
}

function buildUnavailableResolution({ nativeClaudeSessionId, cwd, projectsRoot, reason }) {
  return {
    nativePathState: NATIVE_PATH_STATE_UNAVAILABLE,
    nativeClaudeSessionId: nativeClaudeSessionId || null,
    cwd: cwd || null,
    projectsRoot,
    projectKey: null,
    nativePath: null,
    resolvedBy: null,
    reason,
  };
}

function normalizeCwd(value) {
  const normalized = readNonEmptyString(value);
  if (!normalized) {
    return null;
  }

  if (normalized === path.parse(normalized).root) {
    return normalized;
  }

  return normalized.replace(/[\\/]+$/, "");
}

function sanitizePathSegment(value) {
  return value.replace(/[^A-Za-z0-9._-]+/g, "-");
}

function digestText(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

function setBestEffortFileMode(filePath, fsImpl = fs) {
  try {
    fsImpl.chmodSync(filePath, 0o600);
  } catch {
    // Best-effort only on filesystems without POSIX mode support.
  }
}

function safeExistsSync(fsImpl, filePath) {
  try {
    return fsImpl.existsSync(filePath);
  } catch {
    return false;
  }
}

function uniqueStrings(values) {
  const seen = new Set();
  const result = [];

  for (const value of values) {
    if (!isNonEmptyString(value) || seen.has(value)) {
      continue;
    }
    seen.add(value);
    result.push(value);
  }

  return result;
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

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isNonEmptyString(value) {
  return typeof value === "string" && value.length > 0;
}

module.exports = {
  CLAUDE_PROJECTS_DIRNAME,
  MMSCHAT_TRANSCRIPT_CACHE_DIRNAME,
  MMSCHAT_TRANSCRIPT_CACHE_VERSION,
  NATIVE_PATH_STATE_CONFIRMED,
  NATIVE_PATH_STATE_UNAVAILABLE,
  TRANSCRIPT_SOURCE_NATIVE_JSONL,
  TRANSCRIPT_SOURCE_RAW_FALLBACK,
  buildClaudeProjectKey,
  buildClaudeProjectKeyCandidates,
  buildRawFallbackTranscriptSnapshot,
  buildTranscriptSnapshot,
  parseClaudeNativeJsonl,
  readClaudeNativeJsonlFile,
  readMMSChatTranscriptCache,
  readNativeClaudeTranscriptSnapshot,
  resolveClaudeHomeDir,
  resolveClaudeProjectsDir,
  resolveMMSChatTranscriptCacheDir,
  resolveMMSChatTranscriptCachePath,
  resolveNativeClaudeProjectJsonlPath,
  writeMMSChatTranscriptCache,
};
