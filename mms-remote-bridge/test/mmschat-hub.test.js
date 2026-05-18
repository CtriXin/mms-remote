// FILE: mmschat-hub.test.js
// Purpose: Verifies safe MMSChat bridge RPC stays local-first, cached, and free of live actions.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, fs, os, path, ../src/mmschat-*, ../src/mmschat-transcript

const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");
const assert = require("node:assert/strict");
const { createMMSChatLauncher } = require("../src/mmschat-launcher");
const { createMMSChatHub, handleMMSChatRequest } = require("../src/mmschat-hub");
const { createMMSChatRegistry } = require("../src/mmschat-registry");
const { createMMSChatStore } = require("../src/mmschat-store");
const {
  MMSCHAT_ERROR_CODES,
  MMSCHAT_METHODS,
  MMSCHAT_NATIVE_SESSION_STATUS,
  MMSCHAT_STATUS,
  MMSCHAT_TRANSCRIPT_CACHE_STATE,
} = require("../src/mmschat-protocol");
const {
  buildClaudeProjectKey,
  resolveMMSChatTranscriptCachePath,
  writeMMSChatTranscriptCache,
} = require("../src/mmschat-transcript");

test("mmschat hub attaches explicit metadata, hides sessions, and lists visible sessions only", async () => {
  await withHubFixture(async ({ hub }) => {
    const attached = await hub.handleMethod(MMSCHAT_METHODS.attach, {
      authSecretRef: "keychain:mms/kimi",
      cwd: "/tmp/project-a",
      launchProfileFingerprint: "sha256:profile-a",
      launchProfileName: "fast",
      model: "kimi-k2",
      nativeClaudeSessionId: "native-attach-1",
      provider: "kimi",
      tmuxPaneId: "%12",
      tmuxSessionName: "mmschat-a",
    });
    const second = await hub.handleMethod(MMSCHAT_METHODS.attach, {
      cwd: "/tmp/project-b",
      model: "kimi-k2",
      nativeClaudeSessionId: "native-attach-2",
      provider: "kimi",
      tmuxPaneId: "%14",
      tmuxSessionName: "mmschat-b",
    });

    const hidden = await hub.handleMethod(MMSCHAT_METHODS.hide, {
      hidden: true,
      mmschatId: second.session.mmschatId,
    });
    const listed = await hub.handleMethod(MMSCHAT_METHODS.list, {});
    const listedHidden = await hub.handleMethod(MMSCHAT_METHODS.list, { includeHidden: true });

    assert.equal(attached.attached, true);
    assert.equal(attached.session.status, MMSCHAT_STATUS.pending);
    assert.equal(attached.session.nativeClaudeSessionStatus, MMSCHAT_NATIVE_SESSION_STATUS.confirmed);
    assert.equal(attached.profileSummary.authSecretRefPresent, true);
    assert.equal(attached.profileComparison.status, "last_known_missing");
    assert.equal(hidden.session.hidden, true);
    assert.equal(listed.source, "registry");
    assert.equal(listed.sortedBy, "lastActivityAt");
    assert.deepEqual(listed.sessions.map((session) => session.mmschatId), [attached.session.mmschatId]);
    assert.deepEqual(
      listedHidden.sessions.map((session) => session.mmschatId).sort(),
      [attached.session.mmschatId, second.session.mmschatId].sort()
    );
  });
});

test("mmschat hub detail reads synthetic native transcript, writes cache, and reuses cached detail", async () => {
  await withHubFixture(async ({ claudeHome, env, hub, registry, stateDir }) => {
    const cwd = "/tmp/detail-project";
    const nativeClaudeSessionId = "detail-session-123";
    const session = registry.register({
      authSecretRef: "keychain:mms/detail",
      cwd,
      launchProfileFingerprint: "sha256:detail-profile",
      launchProfileName: "detail",
      mmschatId: "mmschat_detail",
      model: "kimi-k2",
      nativeClaudeSessionId,
      nativeClaudeSessionStatus: MMSCHAT_NATIVE_SESSION_STATUS.confirmed,
      provider: "kimi",
      status: MMSCHAT_STATUS.idle,
    });

    const nativePath = writeSyntheticNativeTranscript({ claudeHome, cwd, nativeClaudeSessionId });
    const detail = await hub.handleMethod(MMSCHAT_METHODS.detail, {
      mmschatId: session.mmschatId,
    });
    const cachePath = resolveMMSChatTranscriptCachePath({
      env,
      mmschatId: session.mmschatId,
    });

    assert.equal(detail.session.transcriptCacheState, MMSCHAT_TRANSCRIPT_CACHE_STATE.fresh);
    assert.equal(detail.transcript.source, "native-jsonl");
    assert.equal(detail.transcript.nativePathState, "confirmed");
    assert.equal(detail.transcript.messages.length, 2);
    assert.equal(detail.transcript.messages[0].content[0].text, "hello from fixture");
    assert.equal(detail.profileSummary.launchProfileName, "detail");
    assert.equal(fs.existsSync(cachePath), true);
    assert.equal(cachePath.startsWith(stateDir), true);

    fs.rmSync(nativePath, { force: true });
    const cachedDetail = await hub.handleMethod(MMSCHAT_METHODS.detail, {
      mmschatId: session.mmschatId,
    });

    assert.deepEqual(cachedDetail.transcript, detail.transcript);
  });
});

test("mmschat hub discovers recent native Claude sessions without leaking transcript text in list", async () => {
  await withHubFixture(async ({ claudeHome, hub }) => {
    const nativeClaudeSessionId = "discover-session-123";
    writeSyntheticNativeTranscript({
      claudeHome,
      cwd: "/tmp/discover-project",
      nativeClaudeSessionId,
      text: "secret transcript text must stay out of list",
    });

    const listed = await hub.handleMethod(MMSCHAT_METHODS.list, { nativeLimit: 10 });
    const discovered = listed.sessions.find((session) => session.nativeClaudeSessionId === nativeClaudeSessionId);

    assert.equal(listed.source, "registry+native-claude");
    assert.equal(discovered.nativeClaudeSessionStatus, MMSCHAT_NATIVE_SESSION_STATUS.confirmed);
    assert.equal(discovered.status, MMSCHAT_STATUS.needsResume);
    assert.equal(discovered.lastPreviewText, null);
    assert.equal(discovered.metadata.source, "native-claude-discovery");
    assert.equal(JSON.stringify(listed).includes("secret transcript text"), false);

    const detail = await hub.handleMethod(MMSCHAT_METHODS.detail, {
      mmschatId: discovered.mmschatId,
    });
    assert.equal(detail.transcript.source, "native-jsonl");
    assert.equal(detail.transcript.messages[0].content[0].text, "secret transcript text must stay out of list");
  });
});

test("mmschat hub lists Codex rollout sessions and reads normalized detail", async () => {
  await withHubFixture(async ({ codexHome, hub }) => {
    writeSyntheticCodexRollout({
      codexHome,
      threadId: "thread-codex-hub",
      userText: "secret Codex prompt must stay out of list",
      commandOutput: "secret command output must stay out of list",
    });

    const listed = await hub.handleMethod(MMSCHAT_METHODS.list, { nativeLimit: 10 });
    const discovered = listed.sessions.find((session) => session.provider === "codex");

    assert.equal(listed.source, "registry+codex-rollout");
    assert.equal(discovered.agent, "codex");
    assert.equal(discovered.metadata.source, "codex-rollout");
    assert.equal(JSON.stringify(listed).includes("secret Codex prompt"), false);
    assert.equal(JSON.stringify(listed).includes("secret command output"), false);

    const detail = await hub.handleMethod(MMSCHAT_METHODS.detail, {
      mmschatId: discovered.mmschatId,
    });
    assert.equal(detail.transcript.source, "codex-rollout");
    assert.equal(detail.transcript.messages[0].role, "user");
    assert.equal(detail.transcript.messages.at(-1).role, "assistant");
    assert.equal(detail.transcript.messages.some((message) => message.role === "reasoning"), true);
    assert.equal(detail.transcript.messages.some((message) => message.content.some((item) => item.kind === "tool_result")), true);
  });
});

test("mmschat hub cache clear removes only derived cache and preserves native transcript", async () => {
  await withHubFixture(async ({ claudeHome, env, hub, registry }) => {
    const cwd = "/tmp/cache-clear-project";
    const nativeClaudeSessionId = "clear-session-456";
    const session = registry.register({
      cwd,
      lastPreviewText: "preview text",
      mmschatId: "mmschat_clear",
      nativeClaudeSessionId,
      nativeClaudeSessionStatus: MMSCHAT_NATIVE_SESSION_STATUS.confirmed,
      status: MMSCHAT_STATUS.idle,
      transcriptCacheState: MMSCHAT_TRANSCRIPT_CACHE_STATE.fresh,
    });
    const nativePath = writeSyntheticNativeTranscript({ claudeHome, cwd, nativeClaudeSessionId });
    const cachePath = resolveMMSChatTranscriptCachePath({
      env,
      mmschatId: session.mmschatId,
    });

    writeMMSChatTranscriptCache({
      source: "native-jsonl",
      nativePathState: "confirmed",
      messages: [
        {
          sessionId: nativeClaudeSessionId,
          role: "assistant",
          content: [{ kind: "text", text: "cached text" }],
        },
      ],
      rawPreviewText: null,
    }, { env, mmschatId: session.mmschatId });

    const cleared = await hub.handleMethod(MMSCHAT_METHODS.clearCache, {
      mmschatId: session.mmschatId,
    });

    assert.equal(cleared.cacheCleared, true);
    assert.equal(cleared.session.mmschatId, session.mmschatId);
    assert.equal(cleared.session.lastPreviewText, null);
    assert.equal(cleared.session.transcriptCacheState, MMSCHAT_TRANSCRIPT_CACHE_STATE.empty);
    assert.equal(fs.existsSync(cachePath), false);
    assert.equal(fs.existsSync(nativePath), true);
  });
});

test("mmschat hub disables send and resume without live opt-in", async () => {
  await withHubFixture(async ({ hub, registry }) => {
    const session = registry.register({
      cwd: "/tmp/live-action-project",
      mmschatId: "mmschat_live_action",
      status: MMSCHAT_STATUS.needsResume,
    });

    const sendResult = await hub.handleMethod(MMSCHAT_METHODS.send, {
      mmschatId: session.mmschatId,
      text: "hello",
      confirmLiveAction: true,
    });
    const resumeResult = await hub.handleMethod(MMSCHAT_METHODS.resume, {
      mmschatId: session.mmschatId,
      confirmLiveAction: true,
    });

    assert.equal(sendResult.accepted, false);
    assert.equal(sendResult.disabled, true);
    assert.equal(sendResult.errorCode, MMSCHAT_ERROR_CODES.sendDisabled);
    assert.equal(resumeResult.resumeStarted, false);
    assert.equal(resumeResult.disabled, true);
    assert.equal(resumeResult.errorCode, MMSCHAT_ERROR_CODES.sendDisabled);

    for (const method of [MMSCHAT_METHODS.kill]) {
      await assert.rejects(
        hub.handleMethod(method, { mmschatId: session.mmschatId }),
        (error) => error?.errorCode === MMSCHAT_ERROR_CODES.unsupportedMethod
      );
    }
  });
});

test("mmschat hub runs send and resume through injected live runner with opt-in", async () => {
  const calls = [];
  const liveActionRunner = {
    async resume(session) {
      calls.push({ action: "resume", session });
      return {
        processAlive: true,
        resumeStarted: true,
        tmuxPaneId: "%31",
        tmuxSessionName: "mmschat-live",
      };
    },
    async send(session, params) {
      calls.push({ action: "send", session, text: params.text });
      return {
        processAlive: true,
        sent: true,
        tmuxPaneId: "%31",
        tmuxSessionName: "mmschat-live",
      };
    },
  };

  await withHubFixture(async ({ hub, registry }) => {
    const session = registry.register({
      cwd: "/tmp/live-action-project",
      mmschatId: "mmschat_live_opt_in",
      nativeClaudeSessionId: "live-native-1",
      status: MMSCHAT_STATUS.needsResume,
    });

    const resumed = await hub.handleMethod(MMSCHAT_METHODS.resume, {
      mmschatId: session.mmschatId,
      confirmLiveAction: true,
    });
    const sent = await hub.handleMethod(MMSCHAT_METHODS.send, {
      mmschatId: session.mmschatId,
      text: "hello live",
      confirmLiveAction: true,
    });

    assert.equal(resumed.disabled, false);
    assert.equal(resumed.resumeStarted, true);
    assert.equal(resumed.session.status, MMSCHAT_STATUS.running);
    assert.equal(sent.accepted, true);
    assert.equal(sent.sent, true);
    assert.equal(sent.session.tmuxPaneId, "%31");
    assert.deepEqual(calls.map((call) => call.action), ["resume", "send"]);
  }, {
    env: { MMSCHAT_LIVE_ACTIONS: "1" },
    liveActionRunner,
  });
});

test("mmschat request dispatcher returns JSON-RPC errors for invalid safe-method params", async () => {
  await withHubFixture(async ({ hub }) => {
    let response = "";
    let resolveResponse;
    const responsePromise = new Promise((resolve) => {
      resolveResponse = resolve;
    });

    const handled = handleMMSChatRequest(
      JSON.stringify({
        id: "attach-invalid-1",
        method: MMSCHAT_METHODS.attach,
        params: {
          cwd: "/tmp/project-a",
          token: "raw-secret",
        },
      }),
      (payload) => {
        response = payload;
        resolveResponse();
      },
      { hub }
    );

    assert.equal(handled, true);
    await responsePromise;
    const parsed = JSON.parse(response);
    assert.equal(parsed.id, "attach-invalid-1");
    assert.equal(parsed.error.data.errorCode, MMSCHAT_ERROR_CODES.secretRejected);
  });
});

function withHubFixture(run, hubOptions = {}) {
  return withTempRoot(async (rootDir) => {
    const stateDir = path.join(rootDir, "state");
    const claudeHome = path.join(rootDir, ".claude");
    const codexHome = path.join(rootDir, ".codex");
    const osImpl = { homedir: () => rootDir };
    const env = {
      ...process.env,
      CODEX_HOME: codexHome,
      MMS_REMOTE_DEVICE_STATE_DIR: stateDir,
    };
    const hubEnv = { ...env, ...(hubOptions.env || {}), CODEX_HOME: codexHome };
    let nextId = 0;
    const store = createMMSChatStore({ env });
    const registry = createMMSChatRegistry({
      generateId: () => `mmschat_fixture_${++nextId}`,
      store,
    });
    const launcher = createMMSChatLauncher({
      buildLaunchPlan(input = {}) {
        return {
          cwd: input.cwd,
          spawn: false,
          profile: compactObject({
            agent: "claude",
            authSecretRef: input.authSecretRef,
            launchProfileFingerprint: input.launchProfileFingerprint,
            launchProfileName: input.launchProfileName,
            model: input.model,
            provider: input.provider,
          }),
        };
      },
      registry,
    });
    const hub = createMMSChatHub({
      env: hubEnv,
      launcher,
      liveActionRunner: hubOptions.liveActionRunner,
      registry,
      transcriptOptions: {
        claudeHome,
        codexHome,
        env: hubEnv,
        osImpl,
      },
    });

    return run({ claudeHome, codexHome, env, hub, launcher, registry, rootDir, stateDir });
  });
}

function writeSyntheticNativeTranscript({ claudeHome, cwd, nativeClaudeSessionId, text = "hello from fixture" }) {
  const projectKey = buildClaudeProjectKey(cwd);
  const nativePath = path.join(
    claudeHome,
    "projects",
    projectKey,
    `${nativeClaudeSessionId}.jsonl`
  );
  const records = [
    {
      message: {
        content: [{ type: "text", text }],
        role: "assistant",
      },
      sessionId: nativeClaudeSessionId,
      timestamp: "2026-05-16T08:29:07.000Z",
      type: "message",
      uuid: "msg-1",
    },
    {
      message: {
        content: [{ type: "thinking", thinking: "safe reasoning preview" }],
        role: "assistant",
      },
      parentUuid: "msg-1",
      sessionId: nativeClaudeSessionId,
      timestamp: "2026-05-16T08:29:08.000Z",
      type: "message",
      uuid: "msg-2",
    },
  ];

  fs.mkdirSync(path.dirname(nativePath), { recursive: true });
  fs.writeFileSync(nativePath, `${records.map((entry) => JSON.stringify(entry)).join("\n")}\n`, "utf8");
  return nativePath;
}

function writeSyntheticCodexRollout({ codexHome, threadId, userText, commandOutput }) {
  const rolloutDir = path.join(codexHome, "sessions", "2026", "05", "17");
  const rolloutPath = path.join(rolloutDir, `rollout-2026-05-17T10-15-00-${threadId}.jsonl`);
  const records = [
    {
      timestamp: "2026-05-17T10:15:00.000Z",
      type: "session_meta",
      payload: {
        id: threadId,
        cwd: "/tmp/codex-hub-project",
        model: "gpt-5.5",
        originator: "codex_cli_rs",
        source: "cli",
      },
    },
    {
      timestamp: "2026-05-17T10:15:01.000Z",
      type: "event_msg",
      payload: {
        type: "user_message",
        message: userText,
      },
    },
    {
      timestamp: "2026-05-17T10:15:02.000Z",
      type: "response_item",
      payload: {
        type: "reasoning",
        summary: [{ text: "inspecting rollout records" }],
      },
    },
    {
      timestamp: "2026-05-17T10:15:03.000Z",
      type: "response_item",
      payload: {
        type: "function_call",
        call_id: "call-hub-1",
        name: "exec_command",
        arguments: JSON.stringify({ cmd: "node --check mmschat-hub.js", cwd: "/tmp/codex-hub-project" }),
      },
    },
    {
      timestamp: "2026-05-17T10:15:04.000Z",
      type: "response_item",
      payload: {
        type: "function_call_output",
        call_id: "call-hub-1",
        output: commandOutput,
      },
    },
    {
      timestamp: "2026-05-17T10:15:05.000Z",
      type: "event_msg",
      payload: {
        type: "agent_message",
        message: "Codex detail ready",
      },
    },
  ];

  fs.mkdirSync(rolloutDir, { recursive: true });
  fs.writeFileSync(rolloutPath, `${records.map((entry) => JSON.stringify(entry)).join("\n")}\n`, "utf8");
  return rolloutPath;
}

function withTempRoot(run) {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-hub-"));
  return Promise.resolve()
    .then(() => run(rootDir))
    .finally(() => {
      fs.rmSync(rootDir, { force: true, recursive: true });
    });
}

function compactObject(value) {
  return Object.fromEntries(Object.entries(value).filter(([, entry]) => entry !== undefined && entry !== null));
}
