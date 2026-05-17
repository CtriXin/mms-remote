// FILE: mmschat-native-discovery.js
// Purpose: Discovers recent native Claude JSONL sessions without exposing transcript text.
// Layer: Transcript metadata helper
// Exports: Bounded native Claude session discovery for MMSChat list/detail attachment.
// Depends on: fs, path, ./mmschat-transcript

const fs = require("fs");
const path = require("path");
const { resolveClaudeProjectsDir } = require("./mmschat-transcript");

const MAX_DISCOVERY_PROJECTS = 64;
const MAX_DISCOVERY_SESSIONS = 80;
const MAX_DISCOVERY_FILE_BYTES = 512_000;
const MAX_DISCOVERY_TITLE_LENGTH = 96;

function discoverNativeClaudeSessions(options = {}) {
  const projectsRoot = resolveClaudeProjectsDir(options);
  const fsImpl = options.fsImpl || fs;
  const maxProjects = readPositiveInteger(options.maxProjects) || MAX_DISCOVERY_PROJECTS;
  const maxSessions = readPositiveInteger(options.maxSessions) || MAX_DISCOVERY_SESSIONS;
  const maxFileBytes = readPositiveInteger(options.maxFileBytes) || MAX_DISCOVERY_FILE_BYTES;

  if (!safeExistsSync(fsImpl, projectsRoot)) {
    return [];
  }

  const projectDirs = safeReadDirents(fsImpl, projectsRoot)
    .filter((entry) => entry?.isDirectory?.())
    .map((entry) => buildDiscoveryProjectCandidate(fsImpl, projectsRoot, entry.name))
    .filter(Boolean)
    .sort(compareDiscoveryCandidates)
    .slice(0, maxProjects);

  return collectDiscoverySessionCandidates(fsImpl, projectDirs)
    .sort(compareDiscoveryCandidates)
    .slice(0, maxSessions)
    .map((candidate) => buildDiscoveredNativeSession(candidate, { fsImpl, maxFileBytes }))
    .filter(Boolean);
}

function collectDiscoverySessionCandidates(fsImpl, projectDirs) {
  return projectDirs.flatMap((project) => {
    return safeReadDirents(fsImpl, project.path)
      .filter((entry) => entry?.isFile?.() && entry.name.endsWith(".jsonl"))
      .map((entry) => buildDiscoverySessionCandidate(fsImpl, project, entry.name))
      .filter(Boolean);
  });
}

function buildDiscoveryProjectCandidate(fsImpl, projectsRoot, projectKey) {
  const projectPath = path.join(projectsRoot, projectKey);
  const stat = safeStatSync(fsImpl, projectPath);
  if (!stat) {
    return null;
  }

  return {
    name: projectKey,
    path: projectPath,
    mtimeMs: toStatTime(stat),
  };
}

function buildDiscoverySessionCandidate(fsImpl, project, fileName) {
  const filePath = path.join(project.path, fileName);
  const stat = safeStatSync(fsImpl, filePath);
  const nativeClaudeSessionId = fileName.replace(/\.jsonl$/, "");
  if (!stat || !nativeClaudeSessionId) {
    return null;
  }

  return {
    filePath,
    nativeClaudeSessionId,
    projectKey: project.name,
    size: Number.isFinite(stat.size) ? stat.size : 0,
    mtime: stat.mtime instanceof Date ? stat.mtime.toISOString() : new Date().toISOString(),
    mtimeMs: toStatTime(stat),
  };
}

function buildDiscoveredNativeSession(candidate, { fsImpl, maxFileBytes }) {
  const metadata = scanNativeClaudeJsonlMetadata(
    readBoundedTextFile(fsImpl, candidate.filePath, maxFileBytes),
    candidate.nativeClaudeSessionId
  );
  const cwd = metadata.cwd || projectKeyToCwdHint(candidate.projectKey);
  const lastActivityAt = metadata.lastTimestamp || candidate.mtime;
  const createdAt = metadata.firstTimestamp || lastActivityAt;
  const title = buildDiscoveredNativeSessionTitle(cwd, candidate.projectKey, candidate.nativeClaudeSessionId);

  return {
    nativeClaudeSessionId: candidate.nativeClaudeSessionId,
    nativeClaudeSessionStatus: "confirmed",
    title,
    cwd,
    project: candidate.projectKey,
    agent: "claude",
    status: "needs-resume",
    createdAt,
    lastActivityAt,
    lastPreviewText: null,
    transcriptCacheState: "empty",
    metadata: compactObject({
      source: "native-claude-discovery",
      projectKey: candidate.projectKey,
      fileMtime: candidate.mtime,
      fileBytes: String(candidate.size),
      recordsScanned: String(metadata.recordsScanned),
      messageCount: String(metadata.messageCount),
      userMessageCount: String(metadata.userMessageCount),
      assistantMessageCount: String(metadata.assistantMessageCount),
      firstTimestamp: metadata.firstTimestamp,
      lastTimestamp: metadata.lastTimestamp,
      nativeIdShort: candidate.nativeClaudeSessionId.slice(0, 12),
    }),
  };
}

function scanNativeClaudeJsonlMetadata(jsonlText, expectedSessionId) {
  const metadata = {
    assistantMessageCount: 0,
    cwd: null,
    firstTimestamp: null,
    lastTimestamp: null,
    messageCount: 0,
    recordsScanned: 0,
    userMessageCount: 0,
  };

  for (const line of String(jsonlText || "").split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }

    let parsed;
    try {
      parsed = JSON.parse(trimmed);
    } catch {
      continue;
    }

    if (!isPlainObject(parsed)) {
      continue;
    }

    const recordSessionId = readNonEmptyString(parsed.sessionId);
    if (expectedSessionId && recordSessionId && recordSessionId !== expectedSessionId) {
      continue;
    }

    metadata.recordsScanned += 1;
    metadata.cwd ||= normalizeCwd(parsed.cwd);
    updateDiscoveryTimestamps(metadata, parsed.timestamp);

    if (isPlainObject(parsed.message)) {
      metadata.messageCount += 1;
      const role = readNonEmptyString(parsed.message.role);
      if (role === "user") {
        metadata.userMessageCount += 1;
      } else if (role === "assistant") {
        metadata.assistantMessageCount += 1;
      }
    }
  }

  return metadata;
}

function updateDiscoveryTimestamps(metadata, value) {
  const timestamp = normalizeTimestamp(value);
  if (!timestamp) {
    return;
  }

  if (!metadata.firstTimestamp || Date.parse(timestamp) < Date.parse(metadata.firstTimestamp)) {
    metadata.firstTimestamp = timestamp;
  }
  if (!metadata.lastTimestamp || Date.parse(timestamp) > Date.parse(metadata.lastTimestamp)) {
    metadata.lastTimestamp = timestamp;
  }
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

function readBoundedTextFile(fsImpl, filePath, maxBytes) {
  const byteLimit = readPositiveInteger(maxBytes) || MAX_DISCOVERY_FILE_BYTES;
  const stat = safeStatSync(fsImpl, filePath);
  if (!stat) {
    return "";
  }

  if (stat.size <= byteLimit || typeof fsImpl.openSync !== "function") {
    try {
      return fsImpl.readFileSync(filePath, "utf8");
    } catch {
      return "";
    }
  }

  let fd = null;
  try {
    fd = fsImpl.openSync(filePath, "r");
    const buffer = Buffer.alloc(byteLimit);
    const bytesRead = fsImpl.readSync(fd, buffer, 0, byteLimit, 0);
    return buffer.subarray(0, bytesRead).toString("utf8");
  } catch {
    return "";
  } finally {
    if (fd !== null) {
      try {
        fsImpl.closeSync(fd);
      } catch {
        // Ignore best-effort descriptor cleanup after bounded discovery reads.
      }
    }
  }
}

function compareDiscoveryCandidates(left, right) {
  return right.mtimeMs - left.mtimeMs;
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

function projectKeyToCwdHint(projectKey) {
  const value = readNonEmptyString(projectKey);
  return value || "unknown-claude-project";
}

function buildDiscoveredNativeSessionTitle(cwd, projectKey, nativeClaudeSessionId) {
  const label = path.basename(readNonEmptyString(cwd) || readNonEmptyString(projectKey) || "Claude session");
  const suffix = readNonEmptyString(nativeClaudeSessionId)?.slice(0, 8);
  return limitText(suffix ? `${label} (${suffix})` : label, MAX_DISCOVERY_TITLE_LENGTH);
}

function normalizeTimestamp(value) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return new Date(value).toISOString();
  }
  return readNonEmptyString(value);
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

function limitText(value, maxLength) {
  const text = readNonEmptyString(value);
  if (!text) {
    return null;
  }
  return text.length > maxLength ? text.slice(0, maxLength) : text;
}

function readPositiveInteger(value) {
  return Number.isInteger(value) && value > 0 ? value : null;
}

function readNonEmptyString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function safeExistsSync(fsImpl, filePath) {
  try {
    return fsImpl.existsSync(filePath);
  } catch {
    return false;
  }
}

function compactObject(value) {
  return Object.fromEntries(Object.entries(value).filter(([, entry]) => entry !== undefined && entry !== null));
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

module.exports = {
  discoverNativeClaudeSessions,
};
