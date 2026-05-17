// FILE: agent-launcher.test.js
// Purpose: Verifies offline MMS launch planning and isolated config directory cleanup without spawning processes.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, fs, os, path, ../src/agent-launcher

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  buildMMSAgentArgv,
  buildMMSAgentLaunchPlan,
  cleanupIsolatedMMSConfigDir,
  createIsolatedMMSConfigDir,
  resolveLaunchProfile,
} = require("../src/agent-launcher");

test("agent launcher creates an isolated MMS config dir from local fixture inputs and cleans it safely", () => {
  withTempRoot(({ rootDir }) => {
    const sourceDir = path.join(rootDir, "source-config");
    fs.mkdirSync(sourceDir, { recursive: true });
    fs.writeFileSync(path.join(sourceDir, "config.toml"), "title = \"fixture\"\n", { mode: 0o600 });
    fs.writeFileSync(path.join(sourceDir, "credentials.sh"), "export API_KEY=secret-from-file\n", { mode: 0o600 });

    const isolated = createIsolatedMMSConfigDir({
      sourceConfigDir: sourceDir,
      tempRoot: rootDir,
    });
    const serialized = JSON.stringify(isolated);

    assert.equal(fs.existsSync(path.join(isolated.configDir, "config.toml")), true);
    assert.equal(fs.existsSync(path.join(isolated.configDir, "credentials.sh")), true);
    assert.equal(fs.existsSync(path.join(isolated.configDir, ".mms-isolated-config")), true);
    assert.doesNotMatch(serialized, /secret-from-file/);

    const cleanup = cleanupIsolatedMMSConfigDir(isolated.configDir);
    assert.equal(cleanup.cleaned, true);
    assert.equal(fs.existsSync(isolated.configDir), false);
  });
});

test("agent launcher builds a dry-run MMS command argv and env without spawning", () => {
  withTempRoot(({ rootDir }) => {
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

    const plan = buildMMSAgentLaunchPlan({
      agent: "claude",
      configDir: isolated.configDir,
      cwd: "/tmp/project-a",
      env: { PATH: "/bin", API_KEY: "raw-env-secret" },
      extraArgs: ["--resume"],
      preset: "fast",
    });
    const serialized = JSON.stringify(plan);

    assert.equal(plan.command, "mms");
    assert.deepEqual(plan.argv, ["claude", "--preset", "fast", "--provider", "kimi", "--model", "kimi-k2", "--resume"]);
    assert.equal(plan.cwd, "/tmp/project-a");
    assert.equal(plan.env.PATH, "/bin");
    assert.equal(plan.env.API_KEY, undefined);
    assert.equal(plan.env.MMS_CONFIG_DIR, isolated.configDir);
    assert.equal(plan.spawn, false);
    assert.equal(plan.profile.provider, "kimi");
    assert.equal(plan.profile.model, "kimi-k2");
    assert.equal(plan.profile.authSecretRef, "keychain:mms/kimi");
    assert.equal(plan.profile.credentialPresent, true);
    assert.match(plan.profile.launchProfileFingerprint, /^sha256:[a-f0-9]{64}$/);
    assert.doesNotMatch(serialized, /sk-live-secret|raw-env-secret/);

    cleanupIsolatedMMSConfigDir(isolated.configDir);
  });
});

test("agent launcher refuses cleanup outside helper-created isolated directories", () => {
  withTempRoot(({ rootDir }) => {
    assert.throws(() => cleanupIsolatedMMSConfigDir(rootDir), /non-isolated/);
  });
});

test("agent launcher profile and argv helpers are deterministic", () => {
  const profile = resolveLaunchProfile({
    agent: "claude",
    preset: "fast",
    config: {
      providers: [{ id: "mimo", defaultModel: "mimo-v2", credentialPresent: true }],
      presets: { fast: { provider: "mimo" } },
    },
  });

  assert.equal(profile.provider, "mimo");
  assert.equal(profile.model, "mimo-v2");
  assert.equal(profile.credentialPresent, true);
  assert.deepEqual(buildMMSAgentArgv({ agent: "claude", provider: "mimo", model: "mimo-v2" }), [
    "claude",
    "--provider",
    "mimo",
    "--model",
    "mimo-v2",
  ]);
});

function withTempRoot(run) {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "mms-agent-launcher-"));

  try {
    return run({ rootDir });
  } finally {
    fs.rmSync(rootDir, { recursive: true, force: true });
  }
}
