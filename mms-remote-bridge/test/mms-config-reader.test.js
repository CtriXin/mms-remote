// FILE: mms-config-reader.test.js
// Purpose: Verifies MMS config path resolution, minimal TOML parsing, and secret-safe metadata extraction.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, fs, os, path, ../src/mms-config-reader

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  parseMMSConfigToml,
  readMMSConfig,
  resolveMMSConfigCandidates,
  resolveMMSConfigPath,
} = require("../src/mms-config-reader");

test("mms config path resolution follows MMS_CONFIG_DIR, XDG_CONFIG_HOME, then ~/.config/mms", () => {
  withTempConfigRoots(({ homeDir, mmsConfigDir, xdgConfigHome }) => {
    const env = {
      MMS_CONFIG_DIR: mmsConfigDir,
      XDG_CONFIG_HOME: xdgConfigHome,
    };
    const osImpl = { homedir: () => homeDir };
    const candidates = resolveMMSConfigCandidates({ env, osImpl });

    assert.deepEqual(candidates.map((candidate) => candidate.source), ["MMS_CONFIG_DIR", "XDG_CONFIG_HOME", "HOME"]);
    assert.equal(resolveMMSConfigPath({ env, osImpl }), path.join(mmsConfigDir, "config.toml"));
    assert.equal(
      resolveMMSConfigPath({ env: { XDG_CONFIG_HOME: xdgConfigHome }, osImpl }),
      path.join(xdgConfigHome, "mms", "config.toml")
    );
    assert.equal(
      resolveMMSConfigPath({ env: {}, osImpl }),
      path.join(homeDir, ".config", "mms", "config.toml")
    );
  });
});

test("mms config reader picks the first existing candidate and returns sanitized provider metadata", () => {
  withTempConfigRoots(({ homeDir, mmsConfigDir, xdgConfigHome }) => {
    writeConfig(path.join(xdgConfigHome, "mms"), `
title = "XDG profile"
visible_providers = ["kimi"]
visible_clis = ["claude"]

[[providers]]
id = "kimi"
name = "Kimi"
cli = "claude"
models = ["kimi-k2", "moonshot-v1"]
default_model = "kimi-k2"
api_key = "sk-live-secret"
auth_secret_ref = "keychain:mms/kimi"
visible = true

[[providers]]
id = "hidden-provider"
cli = "mms-hidden"
token = "do-not-return"
visible = false

[presets.fast]
provider = "kimi"
model = "kimi-k2"
temperature = 0.2
args = ["--profile", "fast"]
credential = "raw-preset-secret"

[overlays.local]
provider = "kimi"
model = "kimi-k2"
enabled = true
`);
    writeConfig(path.join(homeDir, ".config", "mms"), "title = \"Home profile\"");

    const config = readMMSConfig({
      env: { MMS_CONFIG_DIR: mmsConfigDir, XDG_CONFIG_HOME: xdgConfigHome },
      osImpl: { homedir: () => homeDir },
    });
    const serialized = JSON.stringify(config);

    assert.equal(config.found, true);
    assert.equal(config.source, "XDG_CONFIG_HOME");
    assert.equal(config.providers[0].id, "kimi");
    assert.deepEqual(config.providers[0].models, ["kimi-k2", "moonshot-v1"]);
    assert.equal(config.providers[0].defaultModel, "kimi-k2");
    assert.equal(config.providers[0].authSecretRef, "keychain:mms/kimi");
    assert.equal(config.providers[0].credentialPresent, true);
    assert.equal(config.providers[1].visible, false);
    assert.equal(config.providers[1].credentialPresent, true);
    assert.deepEqual(config.visibleProviders, ["kimi"]);
    assert.deepEqual(config.visibleCliIds, ["claude"]);
    assert.equal(config.presets.fast.provider, "kimi");
    assert.equal(config.presets.fast.credentialPresent, true);
    assert.equal(config.overlays.local.enabled, true);
    assert.equal(config.metadata.title, "XDG profile");
    assert.doesNotMatch(serialized, /sk-live-secret|do-not-return|raw-preset-secret/);
  });
});

test("mms config TOML parser supports arrays, comments, dotted tables, and quoted keys", () => {
  const parsed = parseMMSConfigToml(`
title = "dev # not a comment" # real comment
visible_cli_ids = ["claude", "codex"]

[[providers]]
id = "mimo"
models = ["mimo-v2", "mimo-v2.5"]

[presets."release-fast"]
provider = "mimo"
temperature = 0.4
enabled = true
`);

  assert.equal(parsed.title, "dev # not a comment");
  assert.deepEqual(parsed.visible_cli_ids, ["claude", "codex"]);
  assert.equal(parsed.providers[0].id, "mimo");
  assert.equal(parsed.presets["release-fast"].temperature, 0.4);
  assert.equal(parsed.presets["release-fast"].enabled, true);
});

function writeConfig(configDir, content) {
  fs.mkdirSync(configDir, { recursive: true });
  fs.writeFileSync(path.join(configDir, "config.toml"), content, { mode: 0o600 });
}

function withTempConfigRoots(run) {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "mms-config-reader-"));
  const homeDir = path.join(rootDir, "home");
  const mmsConfigDir = path.join(rootDir, "mms-config-dir");
  const xdgConfigHome = path.join(rootDir, "xdg");
  fs.mkdirSync(homeDir, { recursive: true });

  try {
    return run({ homeDir, mmsConfigDir, rootDir, xdgConfigHome });
  } finally {
    fs.rmSync(rootDir, { recursive: true, force: true });
  }
}
