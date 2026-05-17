// FILE: mmschat-registry.test.js
// Purpose: Verifies MMSChat registry CRUD, sorting, secret rejection, and liveness transitions.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, fs, os, path, ../src/mmschat-store, ../src/mmschat-registry, ../src/mmschat-protocol

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { createMMSChatStore } = require("../src/mmschat-store");
const {
  createMMSChatRegistry,
  resolveLivenessStatus,
} = require("../src/mmschat-registry");
const {
  MMSCHAT_ERROR_CODES,
  MMSCHAT_NATIVE_SESSION_STATUS,
  MMSCHAT_STATUS,
  MMSCHAT_TRANSCRIPT_CACHE_STATE,
} = require("../src/mmschat-protocol");

test("mmschat-registry supports register, update, getById, and lastActivity sorting", () => {
  withRegistryFixture(({ registry, advanceClock }) => {
    const first = registry.register({
      mmschatId: "mmschat_first",
      cwd: "/tmp/project-a",
      title: "First",
      status: MMSCHAT_STATUS.pending,
    });

    advanceClock(1_000);
    const second = registry.register({
      mmschatId: "mmschat_second",
      cwd: "/tmp/project-b",
      title: "Second",
      status: MMSCHAT_STATUS.running,
    });

    advanceClock(1_000);
    const updatedFirst = registry.update(first.mmschatId, {
      status: MMSCHAT_STATUS.running,
      lastPreviewText: "latest output",
    });

    assert.equal(updatedFirst.lastPreviewText, "latest output");
    assert.equal(registry.getById(first.mmschatId)?.status, MMSCHAT_STATUS.running);

    const listed = registry.list();
    assert.deepEqual(
      listed.map((session) => session.mmschatId),
      [first.mmschatId, second.mmschatId]
    );
    assert.ok(Date.parse(listed[0].lastActivityAt) > Date.parse(listed[1].lastActivityAt));
  });
});

test("mmschat-registry de-prioritizes empty Codex rollout discoveries", () => {
  withRegistryFixture(({ registry }) => {
    const emptyCodex = registry.register({
      mmschatId: "mmschat_empty_codex",
      cwd: "/tmp/empty-codex",
      provider: "codex",
      status: MMSCHAT_STATUS.idle,
      lastActivityAt: "2026-05-17T10:00:00.000Z",
      transcriptCacheState: MMSCHAT_TRANSCRIPT_CACHE_STATE.empty,
      metadata: {
        source: "codex-rollout",
        messageCount: "0",
      },
    });
    const meaningful = registry.register({
      mmschatId: "mmschat_meaningful",
      cwd: "/tmp/meaningful",
      provider: "codex",
      status: MMSCHAT_STATUS.idle,
      lastActivityAt: "2026-05-10T10:00:00.000Z",
      transcriptCacheState: MMSCHAT_TRANSCRIPT_CACHE_STATE.fresh,
      metadata: {
        source: "codex-rollout",
        messageCount: "2",
      },
    });

    assert.deepEqual(
      registry.list().map((session) => session.mmschatId),
      [meaningful.mmschatId, emptyCodex.mmschatId]
    );
  });
});

test("mmschat-registry rejects secret-like payloads before writing", () => {
  withRegistryFixture(({ registry }) => {
    assert.throws(() => {
      registry.register({
        cwd: "/tmp/project-a",
        metadata: {
          token: "raw-secret",
        },
      });
    }, (error) => error?.errorCode === MMSCHAT_ERROR_CODES.secretRejected);

    assert.deepEqual(registry.list({ includeHidden: true }), []);
  });
});

test("mmschat-registry hide and clearCache preserve identity and native session lookup", () => {
  withRegistryFixture(({ registry, advanceClock }) => {
    const session = registry.register({
      mmschatId: "mmschat_hidden",
      cwd: "/tmp/project-a",
      nativeClaudeSessionId: "native-123",
      nativeClaudeSessionStatus: MMSCHAT_NATIVE_SESSION_STATUS.confirmed,
      status: MMSCHAT_STATUS.idle,
      lastPreviewText: "preview text",
      transcriptCacheState: MMSCHAT_TRANSCRIPT_CACHE_STATE.fresh,
    });

    const originalLastActivityAt = session.lastActivityAt;
    advanceClock(5_000);
    const hidden = registry.hide(session.mmschatId);
    const cleared = registry.clearCache(session.mmschatId);

    assert.equal(hidden.hidden, true);
    assert.equal(registry.list().length, 0);
    assert.equal(registry.list({ includeHidden: true }).length, 1);
    assert.equal(cleared.lastPreviewText, null);
    assert.equal(cleared.transcriptCacheState, MMSCHAT_TRANSCRIPT_CACHE_STATE.empty);
    assert.equal(cleared.lastActivityAt, originalLastActivityAt);
    assert.equal(registry.getByNativeClaudeSessionId("native-123")?.mmschatId, session.mmschatId);
  });
});

test("mmschat-registry liveness transitions move to idle, needs-resume, and dead", () => {
  withRegistryFixture(({ registry }) => {
    const resumable = registry.register({
      mmschatId: "mmschat_resumable",
      cwd: "/tmp/project-a",
      status: MMSCHAT_STATUS.running,
      nativeClaudeSessionId: "native-456",
      nativeClaudeSessionStatus: MMSCHAT_NATIVE_SESSION_STATUS.confirmed,
      pid: 42,
    });
    const detached = registry.register({
      mmschatId: "mmschat_dead",
      cwd: "/tmp/project-b",
      status: MMSCHAT_STATUS.running,
      pid: 84,
    });

    const idle = registry.applyLiveness(resumable.mmschatId, {
      processAlive: true,
      hasActivity: false,
    });
    const needsResume = registry.applyLiveness(resumable.mmschatId, {
      processAlive: false,
    });
    const dead = registry.applyLiveness(detached.mmschatId, {
      processAlive: false,
    });

    assert.equal(idle.status, MMSCHAT_STATUS.idle);
    assert.equal(needsResume.status, MMSCHAT_STATUS.needsResume);
    assert.equal(needsResume.pid, null);
    assert.equal(dead.status, MMSCHAT_STATUS.dead);
    assert.equal(resolveLivenessStatus(resumable, { processAlive: false }), MMSCHAT_STATUS.needsResume);
    assert.equal(resolveLivenessStatus(detached, { processAlive: false }), MMSCHAT_STATUS.dead);
  });
});

function withRegistryFixture(run) {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-registry-"));
  let nowMs = Date.parse("2026-05-16T08:29:07.000Z");
  const store = createMMSChatStore({
    filePath: path.join(rootDir, "mmschat-registry.json"),
  });
  const registry = createMMSChatRegistry({
    store,
    now: () => nowMs,
    generateId: (() => {
      let counter = 0;
      return () => `mmschat_generated_${++counter}`;
    })(),
  });

  try {
    return run({
      advanceClock(deltaMs) {
        nowMs += deltaMs;
      },
      registry,
      rootDir,
    });
  } finally {
    fs.rmSync(rootDir, { recursive: true, force: true });
  }
}
