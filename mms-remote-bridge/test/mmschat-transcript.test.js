// FILE: mmschat-transcript.test.js
// Purpose: Verifies Claude native JSONL resolution, parsing, fallback behavior, and sanitized MMSChat transcript cache writes.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, fs, os, path, ../src/mmschat-transcript

const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  TRANSCRIPT_SOURCE_NATIVE_JSONL,
  TRANSCRIPT_SOURCE_RAW_FALLBACK,
  NATIVE_PATH_STATE_CONFIRMED,
  NATIVE_PATH_STATE_UNAVAILABLE,
  buildClaudeProjectKey,
  buildClaudeProjectKeyCandidates,
  readMMSChatTranscriptCache,
  readNativeClaudeTranscriptSnapshot,
  resolveMMSChatTranscriptCachePath,
  resolveNativeClaudeProjectJsonlPath,
  writeMMSChatTranscriptCache,
} = require("../src/mmschat-transcript");

test("buildClaudeProjectKey derives the Claude projects folder name from cwd", () => {
  assert.equal(
    buildClaudeProjectKey("/Users/xin/auto-skills/CtriXin-repo/mms-remote-p184-mmschat-p3"),
    "-Users-xin-auto-skills-CtriXin-repo-mms-remote-p184-mmschat-p3"
  );

  assert.deepEqual(
    buildClaudeProjectKeyCandidates("/tmp/project name/"),
    ["-tmp-project name", "-tmp-project-name"]
  );
});

test("resolveNativeClaudeProjectJsonlPath finds the derived project key path", () => {
  withTranscriptFixture(({ claudeHome, cwd, sessionId, nativePath }) => {
    const resolved = resolveNativeClaudeProjectJsonlPath({
      claudeHome,
      cwd,
      nativeClaudeSessionId: sessionId,
    });

    assert.equal(resolved.nativePathState, NATIVE_PATH_STATE_CONFIRMED);
    assert.equal(resolved.nativePath, nativePath);
    assert.equal(resolved.resolvedBy, "cwd-key");
  });
});

test("resolveNativeClaudeProjectJsonlPath falls back to scanning the projects root", () => {
  withTempRoot((rootDir) => {
    const claudeHome = path.join(rootDir, ".claude");
    const projectsRoot = path.join(claudeHome, "projects");
    const sessionId = "scan-session-123";
    const nativePath = path.join(projectsRoot, "fixture-project-key", `${sessionId}.jsonl`);
    const cwd = "/tmp/not-the-derived-key";

    fs.mkdirSync(path.dirname(nativePath), { recursive: true });
    fs.writeFileSync(nativePath, `${JSON.stringify(makeRecord({ sessionId, cwd }))}\n`, "utf8");

    const resolved = resolveNativeClaudeProjectJsonlPath({
      claudeHome,
      cwd,
      nativeClaudeSessionId: sessionId,
    });

    assert.equal(resolved.nativePathState, NATIVE_PATH_STATE_CONFIRMED);
    assert.equal(resolved.nativePath, nativePath);
    assert.equal(resolved.resolvedBy, "projects-scan");
  });
});

test("readNativeClaudeTranscriptSnapshot parses supported content blocks without leaking unsupported objects", () => {
  withTranscriptFixture(({ claudeHome, cwd, sessionId }) => {
    const snapshot = readNativeClaudeTranscriptSnapshot({
      claudeHome,
      cwd,
      nativeClaudeSessionId: sessionId,
    });

    assert.equal(snapshot.source, TRANSCRIPT_SOURCE_NATIVE_JSONL);
    assert.equal(snapshot.nativePathState, NATIVE_PATH_STATE_CONFIRMED);
    assert.equal(snapshot.rawPreviewText, null);
    assert.deepEqual(snapshot.messages, [
      {
        sessionId,
        uuid: "msg-user-1",
        parentUuid: null,
        timestamp: "2026-05-16T08:30:00.000Z",
        type: "message",
        role: "user",
        content: [
          {
            kind: "text",
            text: "Hello from the fixture",
          },
        ],
      },
      {
        sessionId,
        uuid: "msg-assistant-1",
        parentUuid: "msg-user-1",
        timestamp: "2026-05-16T08:31:00.000Z",
        type: "message",
        role: "assistant",
        content: [
          {
            kind: "thinking",
            text: "Need to inspect the repository",
          },
          {
            kind: "text",
            text: "I checked the repository state.",
          },
          {
            kind: "tool_use",
            id: "toolu_1",
            name: "bash",
            inputPreviewText: "{\"command\":\"pwd\"}",
          },
          {
            kind: "tool_result",
            toolUseId: "toolu_1",
            isError: false,
            text: "/tmp/project\nbranch clean",
          },
        ],
      },
    ]);
  });
});

test("readNativeClaudeTranscriptSnapshot returns raw fallback when native transcript is missing or corrupt", () => {
  withTempRoot((rootDir) => {
    const claudeHome = path.join(rootDir, ".claude");
    const fallbackText = "recent terminal preview";

    const missingSnapshot = readNativeClaudeTranscriptSnapshot({
      claudeHome,
      cwd: "/tmp/missing-project",
      nativeClaudeSessionId: "missing-session",
      rawPreviewText: fallbackText,
    });

    assert.deepEqual(missingSnapshot, {
      source: TRANSCRIPT_SOURCE_RAW_FALLBACK,
      nativePathState: NATIVE_PATH_STATE_UNAVAILABLE,
      messages: [],
      rawPreviewText: fallbackText,
    });

    const cwd = "/tmp/corrupt-project";
    const projectKey = buildClaudeProjectKey(cwd);
    const corruptPath = path.join(claudeHome, "projects", projectKey, "corrupt-session.jsonl");
    fs.mkdirSync(path.dirname(corruptPath), { recursive: true });
    fs.writeFileSync(corruptPath, "{not-json}\n", "utf8");

    const corruptSnapshot = readNativeClaudeTranscriptSnapshot({
      claudeHome,
      cwd,
      nativeClaudeSessionId: "corrupt-session",
      rawPreviewText: fallbackText,
    });

    assert.deepEqual(corruptSnapshot, {
      source: TRANSCRIPT_SOURCE_RAW_FALLBACK,
      nativePathState: NATIVE_PATH_STATE_UNAVAILABLE,
      messages: [],
      rawPreviewText: fallbackText,
    });
  });
});

test("transcript cache helpers persist sanitized snapshots under the MMSChat state root only", () => {
  withTranscriptFixture(({ claudeHome, cwd, sessionId, nativePath }) => {
    const stateRoot = path.join(path.dirname(claudeHome), "state-root");
    const env = { MMS_REMOTE_DEVICE_STATE_DIR: stateRoot };
    const snapshot = readNativeClaudeTranscriptSnapshot({
      claudeHome,
      cwd,
      nativeClaudeSessionId: sessionId,
    });
    const nativeBefore = fs.readFileSync(nativePath, "utf8");

    const written = writeMMSChatTranscriptCache(snapshot, {
      env,
      nativeClaudeSessionId: sessionId,
      now: () => Date.parse("2026-05-16T08:40:00.000Z"),
      random: () => 0.123456789,
    });
    const cachePath = resolveMMSChatTranscriptCachePath({ env, nativeClaudeSessionId: sessionId });
    const cached = readMMSChatTranscriptCache({ env, nativeClaudeSessionId: sessionId });

    assert.equal(cachePath.startsWith(stateRoot), true);
    assert.equal(fs.existsSync(cachePath), true);
    assert.equal(written.cachedAt, "2026-05-16T08:40:00.000Z");
    assert.equal(cached.cachedAt, "2026-05-16T08:40:00.000Z");
    assert.deepEqual(cached.transcript, snapshot);
    assert.equal(fs.readFileSync(nativePath, "utf8"), nativeBefore);

    const unsafeCachePath = resolveMMSChatTranscriptCachePath({
      env,
      cacheKey: "../outside/native/../escape",
    });
    assert.equal(path.dirname(unsafeCachePath), path.join(stateRoot, "mmschat-transcripts"));
    assert.equal(path.basename(unsafeCachePath), "..-outside-native-..-escape.json");
  });
});

function withTranscriptFixture(run) {
  return withTempRoot((rootDir) => {
    const claudeHome = path.join(rootDir, ".claude");
    const cwd = "/tmp/project name";
    const sessionId = "session-123";
    const projectKey = buildClaudeProjectKey(cwd);
    const nativePath = path.join(claudeHome, "projects", projectKey, `${sessionId}.jsonl`);
    const records = [
      makeRecord({
        sessionId,
        cwd,
        uuid: "msg-user-1",
        parentUuid: null,
        timestamp: "2026-05-16T08:30:00.000Z",
        type: "message",
        role: "user",
        content: "Hello from the fixture",
      }),
      makeRecord({
        sessionId,
        cwd,
        uuid: "msg-assistant-1",
        parentUuid: "msg-user-1",
        timestamp: "2026-05-16T08:31:00.000Z",
        type: "message",
        role: "assistant",
        content: [
          {
            type: "thinking",
            thinking: "Need to inspect the repository",
          },
          {
            type: "text",
            text: "I checked the repository state.",
          },
          {
            type: "tool_use",
            id: "toolu_1",
            name: "bash",
            input: {
              command: "pwd",
            },
          },
          {
            type: "tool_result",
            tool_use_id: "toolu_1",
            content: [
              "/tmp/project",
              {
                type: "text",
                text: "branch clean",
              },
            ],
          },
          {
            type: "unsupported_object",
            secret: {
              token: "should-not-leak",
            },
          },
        ],
      }),
    ];

    fs.mkdirSync(path.dirname(nativePath), { recursive: true });
    fs.writeFileSync(
      nativePath,
      `${records.map((record) => JSON.stringify(record)).join("\n")}\n`,
      "utf8"
    );

    return run({ claudeHome, cwd, sessionId, nativePath });
  });
}

function withTempRoot(run) {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-transcript-"));
  try {
    return run(rootDir);
  } finally {
    fs.rmSync(rootDir, { recursive: true, force: true });
  }
}

function makeRecord({
  sessionId,
  cwd,
  uuid = "msg-1",
  parentUuid = null,
  timestamp = "2026-05-16T08:30:00.000Z",
  type = "message",
  role = "user",
  content = "fixture text",
}) {
  return {
    sessionId,
    cwd,
    uuid,
    parentUuid,
    timestamp,
    type,
    message: {
      role,
      content,
    },
  };
}
