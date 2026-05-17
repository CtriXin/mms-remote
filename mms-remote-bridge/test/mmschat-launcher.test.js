// FILE: mmschat-launcher.test.js
// Purpose: Verifies offline MMS launcher registration without spawning, tmux injection, or live provider calls.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, fs, os, path, ../src/agent-launcher, ../src/mmschat-store, ../src/mmschat-registry, ../src/mmschat-launcher, ../src/mmschat-protocol

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { createIsolatedMMSConfigDir } = require("../src/agent-launcher");
const { createMMSChatRegistry } = require("../src/mmschat-registry");
const { createMMSChatStore } = require("../src/mmschat-store");
const {
  buildPendingMMSChatRegistration,
  createMMSChatLauncher,
} = require("../src/mmschat-launcher");
const {
  MMSCHAT_ERROR_CODES,
  MMSCHAT_NATIVE_SESSION_STATUS,
  MMSCHAT_STATUS,
} = require("../src/mmschat-protocol");

test("mmschat launcher registers a pending session from an offline MMS launch plan", () => {
  withRegistryFixture(({ registry, rootDir }) => {
    const isolated = createIsolatedMMSConfigDir({
      tempRoot: rootDir,
      configToml: `
[[providers]]
id = "kimi"
cli = "claude"
default_model = "kimi-k2"
api_key = "sk-live-secret"
auth_secret_ref = "keychain:mms/kimi"

[presets.fast]
provider = "kimi"
model = "kimi-k2"
`,
    });
    const launcher = createMMSChatLauncher({ registry });

    const session = launcher.registerPendingLaunch({
      mmschatId: "mmschat_launcher_fixture",
      configDir: isolated.configDir,
      cwd: "/tmp/project-a",
      preset: "fast",
      tmuxPaneId: "%12",
      tmuxSessionName: "mmschat-fast",
      pid: 1234,
    });
    const serialized = JSON.stringify(session);

    assert.equal(session.mmschatId, "mmschat_launcher_fixture");
    assert.equal(session.cwd, "/tmp/project-a");
    assert.equal(session.agent, "claude");
    assert.equal(session.provider, "kimi");
    assert.equal(session.model, "kimi-k2");
    assert.equal(session.launchProfileName, "fast");
    assert.match(session.launchProfileFingerprint, /^sha256:[a-f0-9]{64}$/);
    assert.equal(session.authSecretRef, "keychain:mms/kimi");
    assert.equal(session.tmuxPaneId, "%12");
    assert.equal(session.tmuxSessionName, "mmschat-fast");
    assert.equal(session.pid, 1234);
    assert.equal(session.status, MMSCHAT_STATUS.pending);
    assert.equal(session.nativeClaudeSessionId, null);
    assert.equal(session.nativeClaudeSessionStatus, MMSCHAT_NATIVE_SESSION_STATUS.pending);
    assert.equal(registry.list({ includeHidden: true }).length, 1);
    assert.doesNotMatch(serialized, /sk-live-secret/);
  });
});

test("mmschat launcher updates native Claude session state only from explicit caller input", () => {
  withRegistryFixture(({ registry }) => {
    const launcher = createMMSChatLauncher({ registry });
    const session = launcher.registerPendingLaunch({
      cwd: "/tmp/project-b",
      launchPlan: buildNoSpawnLaunchPlan({ cwd: "/tmp/project-b" }),
    });

    const stillPending = launcher.updateNativeClaudeSession({
      mmschatId: session.mmschatId,
      nativeClaudeSessionStatus: MMSCHAT_NATIVE_SESSION_STATUS.pending,
    });
    assert.equal(stillPending.nativeClaudeSessionId, null);
    assert.equal(stillPending.nativeClaudeSessionStatus, MMSCHAT_NATIVE_SESSION_STATUS.pending);

    const confirmed = launcher.updateNativeClaudeSession({
      mmschatId: session.mmschatId,
      nativeClaudeSessionId: "3a0611b9-5577-41ed-a18e-53c7304c79ab",
      nativeClaudeSessionStatus: MMSCHAT_NATIVE_SESSION_STATUS.confirmed,
    });
    assert.equal(confirmed.nativeClaudeSessionId, "3a0611b9-5577-41ed-a18e-53c7304c79ab");
    assert.equal(confirmed.nativeClaudeSessionStatus, MMSCHAT_NATIVE_SESSION_STATUS.confirmed);

    assert.throws(() => {
      launcher.updateNativeClaudeSession({
        mmschatId: session.mmschatId,
        nativeClaudeSessionStatus: MMSCHAT_NATIVE_SESSION_STATUS.confirmed,
      });
    }, (error) => error?.errorCode === MMSCHAT_ERROR_CODES.invalidParams);
  });
});

test("mmschat launcher consumes injected no-spawn plans without persisting command surfaces", () => {
  const buildCalls = [];
  let registered = null;
  const registry = {
    register(input) {
      registered = input;
      return input;
    },
  };
  const launcher = createMMSChatLauncher({
    registry,
    buildLaunchPlan(input) {
      buildCalls.push(input);
      return buildNoSpawnLaunchPlan({
        cwd: input.cwd,
        provider: "mimo",
        model: "mimo-v2",
        launchProfileName: "mimo-fast",
      });
    },
  });

  const session = launcher.registerPendingLaunch({ cwd: "/tmp/project-c" });

  assert.equal(buildCalls.length, 1);
  assert.equal(registered, session);
  assert.equal(session.provider, "mimo");
  assert.equal(session.model, "mimo-v2");
  assert.equal(session.launchProfileName, "mimo-fast");
  assert.equal(session.command, undefined);
  assert.equal(session.argv, undefined);
  assert.equal(session.env, undefined);
  assert.equal(session.status, MMSCHAT_STATUS.pending);

  const source = fs.readFileSync(path.join(__dirname, "../src/mmschat-launcher.js"), "utf8");
  assert.doesNotMatch(source, /child_process|execFile|execSync|spawnSync|send-keys/);
});

test("mmschat launcher rejects secret-like launch plan fields before registry write", () => {
  let writes = 0;
  const registry = {
    register() {
      writes += 1;
      throw new Error("registry should not be reached");
    },
  };
  const launcher = createMMSChatLauncher({ registry });
  const secretCases = [
    ["apiKey", "sk-live-secret"],
    ["token", "raw-token"],
    ["relaySessionId", "relay-session"],
    ["pairingSecret", "pairing-secret"],
  ];

  for (const [field, value] of secretCases) {
    assert.throws(() => {
      launcher.registerPendingLaunch({
        cwd: "/tmp/project-d",
        launchPlan: buildNoSpawnLaunchPlan({
          cwd: "/tmp/project-d",
          profile: {
            agent: "claude",
            provider: "kimi",
            model: "kimi-k2",
            [field]: value,
          },
        }),
      });
    }, (error) => error?.errorCode === MMSCHAT_ERROR_CODES.secretRejected);
  }

  assert.equal(writes, 0);
});

test("mmschat launcher rejects launch plans that would require live spawning", () => {
  assert.throws(() => {
    buildPendingMMSChatRegistration({
      cwd: "/tmp/project-e",
      launchPlan: {
        command: "mms",
        argv: ["claude"],
        cwd: "/tmp/project-e",
        profile: { agent: "claude" },
        spawn: true,
      },
    });
  }, (error) => error?.errorCode === MMSCHAT_ERROR_CODES.invalidParams);
});

function buildNoSpawnLaunchPlan({ cwd, model = "kimi-k2", profile = null, provider = "kimi", launchProfileName = "fast" }) {
  return {
    command: "mms",
    argv: ["claude", "--provider", provider, "--model", model],
    cwd,
    env: { MMS_CONFIG_DIR: "/tmp/mms-config" },
    isolatedConfigDir: "/tmp/mms-config",
    profile: profile || {
      agent: "claude",
      provider,
      model,
      preset: launchProfileName,
      launchProfileName,
      launchProfileFingerprint: "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      authSecretRef: "keychain:mms/test",
    },
    spawn: false,
  };
}

function withRegistryFixture(run) {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "mmschat-launcher-"));
  const store = createMMSChatStore({
    filePath: path.join(rootDir, "mmschat-registry.json"),
  });
  const registry = createMMSChatRegistry({
    store,
    now: () => Date.parse("2026-05-16T08:29:07.000Z"),
    generateId: (() => {
      let counter = 0;
      return () => `mmschat_launcher_${++counter}`;
    })(),
  });

  try {
    return run({ registry, rootDir });
  } finally {
    fs.rmSync(rootDir, { recursive: true, force: true });
  }
}
