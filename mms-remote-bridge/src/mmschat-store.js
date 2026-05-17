// FILE: mmschat-store.js
// Purpose: Persists the local-first MMSChat registry under the existing bridge state root.
// Layer: Persistence helper
// Exports: Store path helpers plus atomic read/write helpers for the MMSChat registry JSON file.
// Depends on: fs, path, ./daemon-state

const fs = require("fs");
const path = require("path");
const { resolveMMSRemoteStateDir } = require("./daemon-state");

const MMSCHAT_STORE_FILE = "mmschat-registry.json";
const MMSCHAT_STORE_VERSION = 1;

function resolveMMSChatStateDir(options = {}) {
  return resolveMMSRemoteStateDir(options);
}

function resolveMMSChatStorePath(options = {}) {
  return options.filePath || path.join(resolveMMSChatStateDir(options), MMSCHAT_STORE_FILE);
}

function createDefaultStoreState() {
  return {
    version: MMSCHAT_STORE_VERSION,
    sessions: [],
  };
}

function createMMSChatStore(options = {}) {
  const fsImpl = options.fsImpl || fs;
  const now = options.now || (() => Date.now());
  const random = options.random || Math.random;
  const filePath = resolveMMSChatStorePath(options);

  return {
    filePath,
    readState() {
      return readMMSChatStoreState({ filePath, fsImpl, now, random });
    },
    readSessions() {
      return this.readState().sessions;
    },
    writeState(state) {
      const normalizedState = normalizeStoreState(state);
      writeMMSChatStoreState(normalizedState, { filePath, fsImpl, now, random });
      return normalizedState;
    },
    writeSessions(sessions) {
      return this.writeState({
        version: MMSCHAT_STORE_VERSION,
        sessions,
      }).sessions;
    },
  };
}

function readMMSChatStoreState({ filePath, fsImpl = fs, now = () => Date.now(), random = Math.random } = {}) {
  const targetPath = resolveMMSChatStorePath({ filePath });
  if (!fsImpl.existsSync(targetPath)) {
    return createDefaultStoreState();
  }

  let serialized;
  try {
    serialized = fsImpl.readFileSync(targetPath, "utf8");
  } catch {
    return createDefaultStoreState();
  }

  try {
    const parsed = JSON.parse(serialized);
    return normalizeStoreState(parsed);
  } catch {
    quarantineCorruptStoreFile({
      filePath: targetPath,
      serialized,
      fsImpl,
      now,
      random,
    });
    return createDefaultStoreState();
  }
}

function writeMMSChatStoreState(state, { filePath, fsImpl = fs, now = () => Date.now(), random = Math.random } = {}) {
  const targetPath = resolveMMSChatStorePath({ filePath });
  const normalizedState = normalizeStoreState(state);
  const serialized = `${JSON.stringify(normalizedState, null, 2)}\n`;
  const targetDir = path.dirname(targetPath);
  const tempPath = buildAtomicTempPath(targetPath, { now, random });

  fsImpl.mkdirSync(targetDir, { recursive: true });

  try {
    fsImpl.writeFileSync(tempPath, serialized, { mode: 0o600 });
    setBestEffortFileMode(tempPath, fsImpl);
    fsImpl.renameSync(tempPath, targetPath);
    setBestEffortFileMode(targetPath, fsImpl);
  } catch (error) {
    try {
      fsImpl.rmSync(tempPath, { force: true });
    } catch {
      // Ignore best-effort cleanup for failed atomic writes.
    }
    throw error;
  }
}

function quarantineCorruptStoreFile({ filePath, serialized, fsImpl = fs, now = () => Date.now(), random = Math.random }) {
  if (!serialized) {
    return null;
  }

  const corruptPath = buildCorruptStorePath(filePath, { now, random });

  try {
    fsImpl.renameSync(filePath, corruptPath);
    setBestEffortFileMode(corruptPath, fsImpl);
    return corruptPath;
  } catch {
    try {
      fsImpl.mkdirSync(path.dirname(corruptPath), { recursive: true });
      fsImpl.writeFileSync(corruptPath, serialized, { mode: 0o600 });
      setBestEffortFileMode(corruptPath, fsImpl);
      return corruptPath;
    } catch {
      return null;
    }
  }
}

function normalizeStoreState(value) {
  if (!isPlainObject(value) || !Array.isArray(value.sessions)) {
    throw new Error("Invalid MMSChat store state.");
  }

  if (value.sessions.some((session) => !isPlainObject(session))) {
    throw new Error("Invalid MMSChat session entry.");
  }

  return {
    version: Number.isInteger(value.version) && value.version > 0 ? value.version : MMSCHAT_STORE_VERSION,
    sessions: cloneJsonValue(value.sessions),
  };
}

function buildAtomicTempPath(filePath, { now = () => Date.now(), random = Math.random } = {}) {
  return path.join(
    path.dirname(filePath),
    `.${path.basename(filePath)}.tmp-${now()}-${randomToken(random)}`
  );
}

function buildCorruptStorePath(filePath, { now = () => Date.now(), random = Math.random } = {}) {
  const extension = path.extname(filePath);
  const basename = path.basename(filePath, extension);
  return path.join(
    path.dirname(filePath),
    `${basename}.corrupt-${now()}-${randomToken(random)}${extension || ".json"}`
  );
}

function randomToken(random) {
  const value = Math.floor(random() * 1_000_000_000);
  return value.toString(36).padStart(6, "0");
}

function setBestEffortFileMode(filePath, fsImpl = fs) {
  try {
    fsImpl.chmodSync(filePath, 0o600);
  } catch {
    // Best-effort only on filesystems without POSIX mode support.
  }
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function cloneJsonValue(value) {
  return JSON.parse(JSON.stringify(value));
}

module.exports = {
  MMSCHAT_STORE_FILE,
  MMSCHAT_STORE_VERSION,
  buildAtomicTempPath,
  buildCorruptStorePath,
  createDefaultStoreState,
  createMMSChatStore,
  normalizeStoreState,
  quarantineCorruptStoreFile,
  readMMSChatStoreState,
  resolveMMSChatStateDir,
  resolveMMSChatStorePath,
  writeMMSChatStoreState,
};
