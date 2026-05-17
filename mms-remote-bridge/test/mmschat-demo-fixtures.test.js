// FILE: mmschat-demo-fixtures.test.js
// Purpose: Verifies local-only MMSChat demo fixture seeding stays secret-free and native-safe.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, fs, os, path, ../src/mmschat-*

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const { createMMSChatHub } = require("../src/mmschat-hub");
const { createMMSChatRegistry } = require("../src/mmschat-registry");
const { createMMSChatStore } = require("../src/mmschat-store");
const {
  MMSCHAT_ERROR_CODES,
  MMSCHAT_METHODS,
  MMSCHAT_TRANSCRIPT_CACHE_STATE,
} = require("../src/mmschat-protocol");
const { resolveMMSChatTranscriptCachePath } = require("../src/mmschat-transcript");

test("mmschat demo seed writes only registry and cache state without secrets", async () => {
  await withDemoHub(async ({ env, hub, nativePath, registry, stateDir }) => {
    const beforeNative = fs.readFileSync(nativePath, "utf8");
    const result = await hub.handleMethod(MMSCHAT_METHODS.demoSeed, { cwd: "/tmp/local-demo-project" });
    const serialized = JSON.stringify(result);

    assert.equal(result.demo, true);
    assert.equal(result.seeded, true);
    assert.equal(result.sessions.length, 2);
    assert.doesNotMatch(serialized, /sk-live|apiKey|authToken|pairingSecret|providerCredential/);
    assert.equal(fs.readFileSync(nativePath, "utf8"), beforeNative);

    const listed = registry.list({});
    assert.equal(listed.length, 2);
    assert.equal(listed[0].transcriptCacheState, MMSCHAT_TRANSCRIPT_CACHE_STATE.fresh);

    const cachePath = resolveMMSChatTranscriptCachePath({
      env,
      mmschatId: listed[0].mmschatId,
    });
    assert.equal(cachePath.startsWith(stateDir), true);
    assert.equal(fs.existsSync(cachePath), true);

    const detail = await hub.handleMethod(MMSCHAT_METHODS.detail, { mmschatId: listed[0].mmschatId });
    assert.equal(detail.transcript.messages.length > 0, true);
  });
});

test("mmschat demo seed rejects secret-like params", async () => {
  await withDemoHub(async ({ hub }) => {
    await assert.rejects(
      () => hub.handleMethod(MMSCHAT_METHODS.demoSeed, { apiKey: "sk-live-secret" }),
      { errorCode: MMSCHAT_ERROR_CODES.secretRejected }
    );
  });
});

function withDemoHub(run) {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-demo-fixture-"));
  const stateDir = path.join(rootDir, "state");
  const claudeHome = path.join(rootDir, ".claude");
  const env = {
    ...process.env,
    MMS_REMOTE_DEVICE_STATE_DIR: stateDir,
  };
  const nativePath = path.join(claudeHome, "projects", "demo", "demo-native-local-1.jsonl");
  fs.mkdirSync(path.dirname(nativePath), { recursive: true });
  fs.writeFileSync(nativePath, "native sentinel\n", "utf8");

  const store = createMMSChatStore({ env });
  const registry = createMMSChatRegistry({ store });
  const hub = createMMSChatHub({
    registry,
    transcriptOptions: {
      claudeHome,
      env,
    },
  });

  return Promise.resolve()
    .then(() => run({ claudeHome, env, hub, nativePath, registry, rootDir, stateDir }))
    .finally(() => {
      fs.rmSync(rootDir, { force: true, recursive: true });
    });
}
