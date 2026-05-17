// FILE: mmschat-store.test.js
// Purpose: Verifies MMSChat registry persistence stays local-first, atomic, and resilient to corrupt JSON.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, fs, os, path, ../src/mmschat-store

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  createMMSChatStore,
  readMMSChatStoreState,
  resolveMMSChatStorePath,
} = require("../src/mmschat-store");

test("mmschat-store uses the existing MMS Remote state root", () => {
  withTempStateDir(({ rootDir }) => {
    assert.equal(resolveMMSChatStorePath(), path.join(rootDir, "mmschat-registry.json"));
  });
});

test("mmschat-store writes with temp-file rename and 0600 permissions", () => {
  withTempStateDir(({ rootDir }) => {
    const operations = [];
    const fsImpl = createRecordingFs(operations);
    const store = createMMSChatStore({
      fsImpl,
      random: () => 0.123456789,
      now: () => 1_716_000_000_000,
    });

    store.writeSessions([
      { mmschatId: "mmschat_atomic", cwd: "/tmp/project" },
    ]);

    const renameOperation = operations.find((operation) => operation.type === "rename");
    assert.ok(renameOperation, "expected an atomic rename");
    assert.match(renameOperation.from, /\.mmschat-registry\.json\.tmp-/);
    assert.equal(renameOperation.to, path.join(rootDir, "mmschat-registry.json"));

    const stored = JSON.parse(fs.readFileSync(store.filePath, "utf8"));
    assert.equal(stored.sessions[0].mmschatId, "mmschat_atomic");
    assert.equal(fs.statSync(store.filePath).mode & 0o777, 0o600);
  });
});

test("mmschat-store falls back safely and quarantines corrupt JSON", () => {
  withTempStateDir(({ rootDir }) => {
    const storePath = path.join(rootDir, "mmschat-registry.json");
    fs.mkdirSync(rootDir, { recursive: true });
    fs.writeFileSync(storePath, "{not valid json", { mode: 0o600 });

    const state = readMMSChatStoreState({
      filePath: storePath,
      now: () => 1_716_000_000_000,
      random: () => 0.75,
    });

    assert.deepEqual(state, { version: 1, sessions: [] });
    assert.equal(fs.existsSync(storePath), false);

    const quarantineFiles = fs.readdirSync(rootDir).filter((entry) => entry.startsWith("mmschat-registry.corrupt-"));
    assert.equal(quarantineFiles.length, 1);
    assert.equal(fs.readFileSync(path.join(rootDir, quarantineFiles[0]), "utf8"), "{not valid json");
  });
});

function withTempStateDir(run) {
  const previousDir = process.env.MMS_REMOTE_DEVICE_STATE_DIR;
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-store-"));
  process.env.MMS_REMOTE_DEVICE_STATE_DIR = rootDir;

  try {
    return run({ rootDir });
  } finally {
    if (previousDir === undefined) {
      delete process.env.MMS_REMOTE_DEVICE_STATE_DIR;
    } else {
      process.env.MMS_REMOTE_DEVICE_STATE_DIR = previousDir;
    }
    fs.rmSync(rootDir, { recursive: true, force: true });
  }
}

function createRecordingFs(operations) {
  return {
    chmodSync(filePath, mode) {
      operations.push({ type: "chmod", filePath, mode });
      return fs.chmodSync(filePath, mode);
    },
    existsSync(filePath) {
      return fs.existsSync(filePath);
    },
    mkdirSync(targetPath, options) {
      return fs.mkdirSync(targetPath, options);
    },
    readFileSync(filePath, encoding) {
      return fs.readFileSync(filePath, encoding);
    },
    renameSync(fromPath, toPath) {
      operations.push({ type: "rename", from: fromPath, to: toPath });
      return fs.renameSync(fromPath, toPath);
    },
    rmSync(targetPath, options) {
      return fs.rmSync(targetPath, options);
    },
    writeFileSync(filePath, contents, options) {
      operations.push({ type: "write", filePath });
      return fs.writeFileSync(filePath, contents, options);
    },
  };
}
