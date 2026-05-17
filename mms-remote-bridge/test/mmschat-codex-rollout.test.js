// FILE: mmschat-codex-rollout.test.js
// Purpose: Verifies Codex CLI/TUI rollout discovery and transcript normalization for MMSChat.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, fs, os, path, ../src/mmschat-codex-rollout

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  discoverCodexRolloutSessions,
  readCodexRolloutTranscriptSnapshot,
} = require("../src/mmschat-codex-rollout");

test("discovers nested Codex CLI rollout sessions without leaking transcript text", (t) => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-rollout-"));
  t.after(() => fs.rmSync(codexHome, { recursive: true, force: true }));

  writeSyntheticCodexRollout({
    codexHome,
    threadId: "thread-redacted",
    userText: "secret prompt must not be listed",
    commandOutput: "secret command output must not be listed",
  });

  const sessions = discoverCodexRolloutSessions({ codexHome });
  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].agent, "codex");
  assert.equal(sessions[0].provider, "codex");
  assert.equal(sessions[0].metadata.source, "codex-rollout");
  assert.equal(sessions[0].metadata.cliSource, "cli");
  assert.equal(JSON.stringify(sessions).includes("secret prompt"), false);
  assert.equal(JSON.stringify(sessions).includes("secret command output"), false);
});

test("skips empty Codex rollout files so mtimes do not look like chat activity", (t) => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-empty-"));
  t.after(() => fs.rmSync(codexHome, { recursive: true, force: true }));

  writeEmptyCodexRollout({ codexHome, threadId: "thread-empty" });

  const sessions = discoverCodexRolloutSessions({ codexHome });
  assert.equal(sessions.length, 0);
});

test("normalizes Codex rollout detail into user assistant reasoning tool and command output items", (t) => {
  const codexHome = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-detail-"));
  t.after(() => fs.rmSync(codexHome, { recursive: true, force: true }));

  writeSyntheticCodexRollout({
    codexHome,
    threadId: "thread-detail",
    assistantText: "final answer from Codex",
    commandOutput: "On branch p8c",
    reasoningText: "checking rollout schema",
    userText: "show git status",
  });

  const [session] = discoverCodexRolloutSessions({ codexHome });
  const transcript = readCodexRolloutTranscriptSnapshot({ codexHome, session });
  const roles = transcript.messages.map((message) => message.role);
  const toolResult = transcript.messages.flatMap((message) => message.content)
    .find((item) => item.kind === "tool_result");

  assert.equal(transcript.source, "codex-rollout");
  assert.equal(transcript.nativePathState, "confirmed");
  assert.deepEqual(roles, ["user", "reasoning", "tool", "tool", "assistant"]);
  assert.equal(transcript.messages[0].content[0].text, "show git status");
  assert.equal(transcript.messages[1].content[0].kind, "thinking");
  assert.equal(toolResult.text, "On branch p8c");
  assert.equal(toolResult.command, "git status");
});

test("falls back to ~/.codex sessions when CODEX_HOME is not supplied", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-home-"));
  const codexHome = path.join(homeDir, ".codex");
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  writeSyntheticCodexRollout({ codexHome, threadId: "thread-fallback" });

  const sessions = discoverCodexRolloutSessions({
    env: {},
    osImpl: { homedir: () => homeDir },
  });

  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].metadata.rolloutIdShort, "thread-fallb");
});

function writeSyntheticCodexRollout({
  codexHome,
  threadId,
  assistantText = "Codex finished",
  commandOutput = "command output",
  reasoningText = "thinking about the task",
  userText = "hello Codex",
}) {
  const rolloutDir = path.join(codexHome, "sessions", "2026", "05", "17");
  const rolloutPath = path.join(rolloutDir, `rollout-2026-05-17T10-00-00-${threadId}.jsonl`);
  const records = [
    {
      timestamp: "2026-05-17T10:00:00.000Z",
      type: "session_meta",
      payload: {
        id: threadId,
        cwd: "/tmp/p8c-project",
        model: "gpt-5.5",
        originator: "codex-tui",
        source: "cli",
      },
    },
    "{schema drift",
    {
      timestamp: "2026-05-17T10:00:01.000Z",
      type: "event_msg",
      payload: {
        type: "user_message",
        message: userText,
      },
    },
    {
      timestamp: "2026-05-17T10:00:02.000Z",
      type: "response_item",
      payload: {
        type: "reasoning",
        summary: [{ text: reasoningText }],
      },
    },
    {
      timestamp: "2026-05-17T10:00:03.000Z",
      type: "response_item",
      payload: {
        type: "function_call",
        call_id: "call-1",
        name: "exec_command",
        arguments: JSON.stringify({ cmd: "git status", cwd: "/tmp/p8c-project" }),
      },
    },
    {
      timestamp: "2026-05-17T10:00:04.000Z",
      type: "response_item",
      payload: {
        type: "function_call_output",
        call_id: "call-1",
        output: commandOutput,
      },
    },
    {
      timestamp: "2026-05-17T10:00:05.000Z",
      type: "event_msg",
      payload: {
        type: "agent_message",
        message: assistantText,
      },
    },
  ];

  fs.mkdirSync(rolloutDir, { recursive: true });
  fs.writeFileSync(
    rolloutPath,
    `${records.map((entry) => typeof entry === "string" ? entry : JSON.stringify(entry)).join("\n")}\n`,
    "utf8"
  );
  return rolloutPath;
}

function writeEmptyCodexRollout({ codexHome, threadId }) {
  const rolloutDir = path.join(codexHome, "sessions", "2026", "05", "17");
  const rolloutPath = path.join(rolloutDir, `rollout-2026-05-17T10-00-00-${threadId}.jsonl`);
  const records = [
    {
      timestamp: "2026-05-17T10:00:00.000Z",
      type: "session_meta",
      payload: {
        id: threadId,
        cwd: "/tmp/empty-rollout-project",
        model: "gpt-5.5",
        originator: "codex-tui",
        source: "cli",
      },
    },
  ];

  fs.mkdirSync(rolloutDir, { recursive: true });
  fs.writeFileSync(rolloutPath, `${records.map((entry) => JSON.stringify(entry)).join("\n")}\n`, "utf8");
  return rolloutPath;
}
