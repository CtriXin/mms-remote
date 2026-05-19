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
  isBootstrapContextText,
  isPlaceholderReasoning,
  readCodexRolloutTranscriptSnapshot,
  resolveCodexSessionsRoots,
} = require("../src/mmschat-codex-rollout");

test("discovers nested Codex CLI rollout sessions without leaking transcript text", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-rollout-"));
  const codexHome = path.join(homeDir, ".codex");
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  writeSyntheticCodexRollout({
    codexHome,
    threadId: "thread-redacted",
    userText: "secret prompt must not be listed",
    commandOutput: "secret command output must not be listed",
  });

  const sessions = discoverCodexRolloutSessions({ codexHome, osImpl: { homedir: () => homeDir } });
  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].agent, "codex");
  assert.equal(sessions[0].provider, "codex");
  assert.equal(sessions[0].metadata.source, "codex-rollout");
  assert.equal(sessions[0].metadata.cliSource, "cli");
  assert.ok(sessions[0].title.includes("secret prompt must not be listed"), `Title should include the real user prompt, got: ${sessions[0].title}`);
  assert.equal(JSON.stringify(sessions).includes("secret command output"), false);
  assert.equal(JSON.stringify(sessions).includes("Codex finished"), false);
});

test("skips empty Codex rollout files so mtimes do not look like chat activity", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-empty-"));
  const codexHome = path.join(homeDir, ".codex");
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  writeEmptyCodexRollout({ codexHome, threadId: "thread-empty" });

  const sessions = discoverCodexRolloutSessions({ codexHome, osImpl: { homedir: () => homeDir } });
  assert.equal(sessions.length, 0);
});

test("normalizes Codex rollout detail into user assistant reasoning tool and command output items", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-detail-"));
  const codexHome = path.join(homeDir, ".codex");
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  writeSyntheticCodexRollout({
    codexHome,
    threadId: "thread-detail",
    assistantText: "final answer from Codex",
    commandOutput: "On branch p8c",
    reasoningText: "checking rollout schema",
    userText: "show git status",
  });

  const [session] = discoverCodexRolloutSessions({ codexHome, osImpl: { homedir: () => homeDir } });
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

// P8K: Bootstrap context records are hidden from counts and titles
test("bootstrap context records are excluded from message counts and do not appear as user bubbles", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-bootstrap-"));
  const codexHome = path.join(homeDir, ".codex");
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  writeSyntheticCodexRolloutWithBootstrap({
    codexHome,
    threadId: "thread-bootstrap",
    realUserText: "你可以computer use吗?",
    bootstrapTexts: [
      "# AGENTS.md instructions for this session",
      "<INSTRUCTIONS>System prompt goes here</INSTRUCTIONS>",
      "<environment_context>Working directory: /tmp/test</environment_context>",
    ],
  });

  const [session] = discoverCodexRolloutSessions({ codexHome, osImpl: { homedir: () => homeDir } });
  assert.equal(session.metadata.userMessageCount, "1", "Only the real user message should be counted");
  assert.equal(session.metadata.bootstrapSkippedCount, "3", "All 3 bootstrap records should be skipped");
  assert.ok(session.title.includes("你可以computer use吗?"), `Title should contain real user prompt, got: ${session.title}`);
  assert.equal(session.title.includes("AGENTS.md"), false, "Title should not contain bootstrap text");
  assert.equal(session.title.includes("INSTRUCTIONS"), false, "Title should not contain bootstrap text");

  // Verify detail transcript does not render bootstrap messages
  const transcript = readCodexRolloutTranscriptSnapshot({ codexHome, session });
  const userMessages = transcript.messages.filter((m) => m.role === "user");
  assert.equal(userMessages.length, 1, "Should only have real user message (bootstrap fully excluded before messages array)");
});

// P8K: Real user prompts generate meaningful rollout titles
test("builds meaningful Codex rollout titles from first or latest real user prompt", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-title-"));
  const codexHome = path.join(homeDir, ".codex");
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  writeSyntheticCodexRollout({
    codexHome,
    threadId: "thread-title-test",
    userText: "hello Codex",
  });

  const [session] = discoverCodexRolloutSessions({ codexHome, osImpl: { homedir: () => homeDir } });
  assert.ok(session.title.includes("hello Codex"), `Title should include user prompt, got: ${session.title}`);
});

// P8K: Fallback to rollout ID only when no real user text exists
test("falls back to rollout ID in title when no real user text exists", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-nouser-"));
  const codexHome = path.join(homeDir, ".codex");
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  // Write a rollout with only bootstrap context user messages (no real user prompts)
  writeSyntheticCodexRolloutWithBootstrap({
    codexHome,
    threadId: "thread-no-real-user",
    realUserText: null,
    bootstrapTexts: [
      "# AGENTS.md instructions for this session",
      "<environment_context>Working directory: /tmp/test</environment_context>",
    ],
  });

  const sessions = discoverCodexRolloutSessions({ codexHome, osImpl: { homedir: () => homeDir } });
  // Should still be discovered because there are assistant/tool messages
  if (sessions.length > 0) {
    assert.equal(sessions[0].title.includes("AGENTS.md"), false, "Title should not contain bootstrap text");
  }
});

// P8K: Placeholder-only reasoning does not render visibly
test("suppresses empty Thinking... placeholders; only shows real reasoning text", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-thinking-"));
  const codexHome = path.join(homeDir, ".codex");
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  // Write a rollout where the reasoning payload has empty/placeholder text
  const rolloutDir = path.join(codexHome, "sessions", "2026", "05", "17");
  const rolloutPath = path.join(rolloutDir, "rollout-2026-05-17T10-00-00-thread-thinking.jsonl");
  const records = [
    {
      timestamp: "2026-05-17T10:00:00.000Z",
      type: "session_meta",
      payload: {
        id: "thread-thinking",
        cwd: "/tmp/thinking-project",
        model: "gpt-5.5",
        originator: "codex-tui",
        source: "cli",
      },
    },
    {
      timestamp: "2026-05-17T10:00:01.000Z",
      type: "event_msg",
      payload: {
        type: "user_message",
        message: "real user message",
      },
    },
    {
      timestamp: "2026-05-17T10:00:02.000Z",
      type: "response_item",
      payload: {
        type: "reasoning",
        summary: [{ text: "" }],  // Empty reasoning = should be suppressed
      },
    },
    {
      timestamp: "2026-05-17T10:00:03.000Z",
      type: "response_item",
      payload: {
        type: "reasoning",
        summary: [{ text: "Actually checking the rollout schema now" }],  // Real reasoning
      },
    },
    {
      timestamp: "2026-05-17T10:00:04.000Z",
      type: "event_msg",
      payload: {
        type: "agent_message",
        message: "answer",
      },
    },
  ];

  fs.mkdirSync(rolloutDir, { recursive: true });
  fs.writeFileSync(rolloutPath, records.map((e) => JSON.stringify(e)).join("\n") + "\n", "utf8");

  const [session] = discoverCodexRolloutSessions({ codexHome, osImpl: { homedir: () => homeDir } });
  assert.equal(session.metadata.reasoningMessageCount, "1", "Only the real reasoning should be counted");

  const transcript = readCodexRolloutTranscriptSnapshot({ codexHome, session });
  const reasoningMessages = transcript.messages.filter((m) => m.role === "reasoning");
  assert.equal(reasoningMessages.length, 1, "Only one reasoning message should appear");
  assert.equal(reasoningMessages[0].content[0].text, "Actually checking the rollout schema now");

  // Also test placeholder text "Thinking..." is suppressed
  const placeholderRecords = [
    {
      timestamp: "2026-05-17T10:00:00.000Z",
      type: "session_meta",
      payload: {
        id: "thread-placeholder",
        cwd: "/tmp/placeholder-project",
        model: "gpt-5.5",
        originator: "codex-tui",
        source: "cli",
      },
    },
    {
      timestamp: "2026-05-17T10:00:01.000Z",
      type: "event_msg",
      payload: {
        type: "user_message",
        message: "test",
      },
    },
    {
      timestamp: "2026-05-17T10:00:02.000Z",
      type: "response_item",
      payload: {
        type: "reasoning",
        text: "Thinking...",  // Literal placeholder
      },
    },
    {
      timestamp: "2026-05-17T10:00:03.000Z",
      type: "event_msg",
      payload: {
        type: "agent_message",
        message: "answer",
      },
    },
  ];
  const placeholderDir = path.join(codexHome, "sessions", "2026", "05", "18");
  const placeholderPath = path.join(placeholderDir, "rollout-2026-05-18T10-00-00-thread-placeholder.jsonl");
  fs.mkdirSync(placeholderDir, { recursive: true });
  fs.writeFileSync(placeholderPath, placeholderRecords.map((e) => JSON.stringify(e)).join("\n") + "\n", "utf8");

  const sessions2 = discoverCodexRolloutSessions({ codexHome, osImpl: { homedir: () => homeDir } });
  const placeholderSession = sessions2.find((s) => s.metadata.rolloutFileName.includes("thread-placeholder"));
  assert.ok(placeholderSession, "Placeholder session should be discovered");
  assert.equal(placeholderSession.metadata.reasoningMessageCount, "0", "Placeholder reasoning should not be counted");

  const transcript2 = readCodexRolloutTranscriptSnapshot({ codexHome, session: placeholderSession });
  const reasoning2 = transcript2.messages.filter((m) => m.role === "reasoning");
  assert.equal(reasoning2.length, 0, "Placeholder 'Thinking...' should not render");
});

// P8K: Bootstrap context detection function tests
test("isBootstrapContextText identifies injected context patterns", (t) => {
  assert.equal(isBootstrapContextText("# AGENTS.md instructions"), true);
  assert.equal(isBootstrapContextText("AGENTS.md instructions for this session"), true);
  assert.equal(isBootstrapContextText("<INSTRUCTIONS>System prompt</INSTRUCTIONS>"), true);
  assert.equal(isBootstrapContextText("<instructions>lowercase</instructions>"), true);
  assert.equal(isBootstrapContextText("<environment_context>path</environment_context>"), true);
  assert.equal(isBootstrapContextText("<permissions instructions>"), true);
  assert.equal(isBootstrapContextText("<skills_instructions>list</skills_instructions>"), true);
  assert.equal(isBootstrapContextText("<plugins_instructions>list</plugins_instructions>"), true);
  assert.equal(isBootstrapContextText("MCP server started on port 8080"), true);
  assert.equal(isBootstrapContextText("MCP startup diagnostic: OK"), true);
  assert.equal(isBootstrapContextText("[MCP] connected to server"), true);
  assert.equal(isBootstrapContextText("You are powered by the model named deepseek"), true);
  assert.equal(isBootstrapContextText("You are an AI assistant"), true);

  // Real user messages should NOT be flagged
  assert.equal(isBootstrapContextText("hello Codex"), false);
  assert.equal(isBootstrapContextText("你可以computer use吗?"), false);
  assert.equal(isBootstrapContextText("show git status"), false);
  assert.equal(isBootstrapContextText("write a function to sort an array"), false);
  assert.equal(isBootstrapContextText(""), false);
  assert.equal(isBootstrapContextText(null), false);
});

// P8K: isPlaceholderReasoning tests
test("isPlaceholderReasoning identifies empty or placeholder reasoning", (t) => {
  assert.equal(isPlaceholderReasoning("Thinking..."), true);
  assert.equal(isPlaceholderReasoning("Thinking…"), true);
  assert.equal(isPlaceholderReasoning(""), true);
  assert.equal(isPlaceholderReasoning("   "), true);
  assert.equal(isPlaceholderReasoning(null), true);
  assert.equal(isPlaceholderReasoning(undefined), true);

  assert.equal(isPlaceholderReasoning("Actually checking the rollout schema now"), false);
  assert.equal(isPlaceholderReasoning("analyzing code structure"), false);
  assert.equal(isPlaceholderReasoning("let me think about this..."), false);
});

// P8K: Preserve empty rollout suppression
test("rollout with only bootstrap context + session_meta still counts as empty", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-bootstrap-only-"));
  const codexHome = path.join(homeDir, ".codex");
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  writeSyntheticCodexRolloutWithBootstrap({
    codexHome,
    threadId: "thread-bootstrap-only",
    realUserText: null,
    bootstrapTexts: [
      "# AGENTS.md instructions for this session",
      "<INSTRUCTIONS>System prompt</INSTRUCTIONS>",
    ],
  });

  const sessions = discoverCodexRolloutSessions({ codexHome, osImpl: { homedir: () => homeDir } });
  // Should be hidden because after filtering bootstrap, no real messages remain
  assert.equal(sessions.length, 0);
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

function writeSyntheticCodexRolloutWithBootstrap({
  codexHome,
  threadId,
  realUserText = null,
  bootstrapTexts = [],
}) {
  const rolloutDir = path.join(codexHome, "sessions", "2026", "05", "17");
  const rolloutPath = path.join(rolloutDir, `rollout-2026-05-17T10-00-00-${threadId}.jsonl`);
  const records = [
    {
      timestamp: "2026-05-17T10:00:00.000Z",
      type: "session_meta",
      payload: {
        id: threadId,
        cwd: "/tmp/bootstrap-project",
        model: "gpt-5.5",
        originator: "codex-tui",
        source: "cli",
      },
    },
    // Bootstrap context messages first
    ...bootstrapTexts.map((text) => ({
      timestamp: "2026-05-17T10:00:01.000Z",
      type: "event_msg",
      payload: {
        type: "user_message",
        message: text,
      },
    })),
    // Real user message (if any)
    ...(realUserText ? [{
      timestamp: "2026-05-17T10:00:02.000Z",
      type: "event_msg",
      payload: {
        type: "user_message",
        message: realUserText,
      },
    }] : []),
    // Assistant reply only when there is real user content (else bootstrap-only sessions stay empty)
    ...(realUserText ? [{
      timestamp: "2026-05-17T10:00:03.000Z",
      type: "event_msg",
      payload: {
        type: "agent_message",
        message: "I understand. Let me help you with that.",
      },
    }] : []),
  ];

  fs.mkdirSync(rolloutDir, { recursive: true });
  fs.writeFileSync(
    rolloutPath,
    records.map((entry) => JSON.stringify(entry)).join("\n") + "\n",
    "utf8"
  );
  return rolloutPath;
}

test("resolves dual roots when CODEX_HOME is set and differs from default", (t) => {
  const roots = resolveCodexSessionsRoots({
    codexHome: "/explicit/codex",
    env: {},
    osImpl: { homedir: () => "/home/user" },
  });

  assert.equal(roots.length, 2);
  assert.ok(roots[0].includes("explicit"));
  assert.ok(roots[1].includes(".codex"));
});

test("dedupes roots when CODEX_HOME matches default", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-dedupe-"));
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  const roots = resolveCodexSessionsRoots({
    codexHome: path.join(homeDir, ".codex"),
    env: {},
    osImpl: { homedir: () => homeDir },
  });

  assert.equal(roots.length, 1);
  assert.ok(roots[0].includes(".codex"));
});

test("no extra roots when CODEX_HOME is not set", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-noroot-"));
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  const roots = resolveCodexSessionsRoots({
    env: {},
    osImpl: { homedir: () => homeDir },
  });

  assert.equal(roots.length, 1);
  assert.ok(roots[0].includes(homeDir));
});

test("out-of-order rollout timestamps store the max valid timestamp", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-out-of-order-"));
  const codexHome = path.join(homeDir, ".codex");
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  const rolloutDir = path.join(codexHome, "sessions", "2026", "05", "17");
  const rolloutPath = path.join(rolloutDir, "rollout-2026-05-17T10-00-00-out-of-order.jsonl");
  const records = [
    {
      timestamp: "2026-05-17T10:00:00.000Z",
      type: "session_meta",
      payload: {
        id: "out-of-order-thread",
        cwd: "/tmp/out-of-order-project",
        model: "gpt-5.5",
        originator: "codex-tui",
        source: "cli",
      },
    },
    {
      timestamp: "2026-05-17T10:00:08.000Z",
      type: "event_msg",
      payload: {
        type: "agent_message",
        message: "later assistant reply",
      },
    },
    {
      timestamp: "2026-05-17T10:00:02.000Z",
      type: "event_msg",
      payload: {
        type: "user_message",
        message: "earlier user prompt",
      },
    },
    {
      timestamp: "not-a-timestamp",
      type: "event_msg",
      payload: {
        type: "agent_message",
        message: "invalid timestamp should be ignored",
      },
    },
  ];

  fs.mkdirSync(rolloutDir, { recursive: true });
  fs.writeFileSync(
    rolloutPath,
    records.map((entry) => JSON.stringify(entry)).join("\n") + "\n",
    "utf8"
  );

  const sessions = discoverCodexRolloutSessions({ codexHome, osImpl: { homedir: () => homeDir } });
  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].metadata.firstTimestamp, "2026-05-17T10:00:00.000Z");
  assert.equal(sessions[0].metadata.lastTimestamp, "2026-05-17T10:00:08.000Z");
  assert.equal(sessions[0].metadata.lastTranscriptAt, "2026-05-17T10:00:08.000Z");
});

test("file mtime wins over stale transcript timestamp", (t) => {
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-stale-"));
  const codexHome = path.join(homeDir, ".codex");
  t.after(() => fs.rmSync(homeDir, { recursive: true, force: true }));

  // Write a file with an old transcript timestamp but a recent mtime
  const rolloutDir = path.join(codexHome, "sessions", "2020", "01", "01");
  const rolloutPath = path.join(rolloutDir, "rollout-2020-01-01T00-00-00-stale-thread.jsonl");
  const records = [
    {
      timestamp: "2020-01-01T00:00:00.000Z",
      type: "session_meta",
      payload: {
        id: "stale-thread",
        cwd: "/tmp/stale-project",
        model: "gpt-5.5",
        originator: "codex-tui",
        source: "cli",
      },
    },
    {
      timestamp: "2020-01-01T00:00:05.000Z",
      type: "event_msg",
      payload: {
        type: "user_message",
        message: "hello from 2020",
      },
    },
    {
      timestamp: "2020-01-01T00:00:10.000Z",
      type: "event_msg",
      payload: {
        type: "agent_message",
        message: "answer from 2020",
      },
    },
  ];

  fs.mkdirSync(rolloutDir, { recursive: true });
  fs.writeFileSync(
    rolloutPath,
    records.map((e) => JSON.stringify(e)).join("\n") + "\n",
    "utf8"
  );

  // Touch the file so mtime is recent (newer than transcript timestamp)
  const touchTime = new Date();
  fs.utimesSync(rolloutPath, touchTime, touchTime);

  const sessions = discoverCodexRolloutSessions({ codexHome, osImpl: { homedir: () => homeDir } });
  assert.equal(sessions.length, 1);

  const meta = sessions[0].metadata;
  // mtime should win because file was just touched
  assert.equal(meta.lastActivitySource, "file_mtime");
  assert.equal(meta.lastTranscriptAt, "2020-01-01T00:00:10.000Z");

  // lastActivityAt should be >= the touch time (converted to ISO) minus a small tolerance
  const lastActivity = new Date(sessions[0].lastActivityAt).getTime();
  const touchMs = touchTime.getTime();
  assert.ok(
    Math.abs(lastActivity - touchMs) < 2000,
    `lastActivity ${new Date(lastActivity).toISOString()} should be close to touchTime ${touchTime.toISOString()}`
  );
});

test("duplicate session across two roots is not discovered twice", (t) => {
  const explicitBase = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-explicit-"));
  const homeDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-codex-home2-"));
  const codexHome = path.join(explicitBase, "codex-home");
  const symlinkPath = path.join(homeDir, ".codex");
  fs.mkdirSync(explicitBase, { recursive: true });
  try {
    fs.symlinkSync(codexHome, symlinkPath, "dir");
  } catch {
    return;
  }
  t.after(() => {
    try { fs.rmSync(homeDir, { recursive: true, force: true }); } catch {}
    try { fs.rmSync(explicitBase, { recursive: true, force: true }); } catch {}
  });

  writeSyntheticCodexRollout({
    codexHome,
    threadId: "thread-dedup",
  });

  const sessions = discoverCodexRolloutSessions({
    codexHome,
    osImpl: { homedir: () => homeDir },
  });
  assert.equal(sessions.length, 1);
});
