// FILE: mms-metadata-hub.test.js
// Purpose: Verifies secret-safe MMS metadata RPC and dry-run launch plan behavior.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, fs, os, path, ../src/mms-metadata-hub

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const {
  MMS_METADATA_ERROR_CODES,
  MMS_METADATA_METHODS,
  createMMSMetadataHub,
  handleMMSMetadataRequest,
} = require("../src/mms-metadata-hub");

test("mms metadata hub returns visible providers, presets, and models without secrets", () => {
  withTempMMSConfig(({ mmsConfigDir }) => {
    const hub = createMMSMetadataHub({
      env: { MMS_CONFIG_DIR: mmsConfigDir },
    });

    const providers = hub.handleMethod(MMS_METADATA_METHODS.providers);
    const presets = hub.handleMethod(MMS_METADATA_METHODS.presets);
    const models = hub.handleMethod(MMS_METADATA_METHODS.models);
    const serialized = JSON.stringify({ providers, presets, models });

    assert.equal(providers.found, true);
    assert.deepEqual(providers.providers, [
      {
        id: "kimi",
        name: "Kimi",
        defaultModel: "kimi-k2",
        models: ["kimi-k2", "moonshot-v1"],
        visible: true,
        credentialPresent: true,
      },
    ]);
    assert.deepEqual(presets.presets, [
      {
        id: "fast",
        provider: "kimi",
        model: "kimi-k2",
        defaultModel: "kimi-k2",
        visible: true,
        credentialPresent: true,
      },
    ]);
    assert.equal(models.models.length, 2);
    assert.equal(models.models[0].id, "kimi:kimi-k2");
    assert.equal(models.models[0].isDefault, true);
    assert.doesNotMatch(serialized, /sk-live-secret|hidden-secret|raw-preset-secret|keychain:mms\/kimi/);
  });
});

test("mms metadata hub builds dry-run launch plans without spawning or exposing secret refs", () => {
  withTempMMSConfig(({ mmsConfigDir }) => {
    const hub = createMMSMetadataHub({
      env: { MMS_CONFIG_DIR: mmsConfigDir },
    });

    const result = hub.handleMethod(MMS_METADATA_METHODS.launchPlan, {
      cwd: "/tmp/project-a",
      preset: "fast",
    });
    const serialized = JSON.stringify(result);

    assert.equal(result.dryRun, true);
    assert.equal(result.command, "mms");
    assert.deepEqual(result.argv, ["claude", "--preset", "fast", "--provider", "kimi", "--model", "kimi-k2"]);
    assert.equal(result.cwd, "/tmp/project-a");
    assert.equal(result.spawn, false);
    assert.equal(result.profile.provider, "kimi");
    assert.equal(result.profile.model, "kimi-k2");
    assert.equal(result.profile.credentialPresent, true);
    assert.match(result.profile.launchProfileFingerprint, /^sha256:[a-f0-9]{64}$/);
    assert.doesNotMatch(serialized, /sk-live-secret|raw-preset-secret|keychain:mms\/kimi|authSecretRef/);
  });
});

test("mms metadata hub rejects invalid launch params as JSON-RPC errors", async () => {
  withTempMMSConfig(async ({ mmsConfigDir }) => {
    let response = "";
    let resolveResponse;
    const responsePromise = new Promise((resolve) => {
      resolveResponse = resolve;
    });

    const handled = handleMMSMetadataRequest(
      JSON.stringify({
        id: "plan-1",
        method: "mms/launch/plan",
        params: { cwd: "/tmp/project-a", apiKey: "raw-secret", preset: "fast" },
      }),
      (payload) => {
        response = payload;
        resolveResponse();
      },
      { env: { MMS_CONFIG_DIR: mmsConfigDir } }
    );

    assert.equal(handled, true);
    await responsePromise;
    const parsed = JSON.parse(response);
    assert.equal(parsed.id, "plan-1");
    assert.equal(parsed.error.data.errorCode, MMS_METADATA_ERROR_CODES.secretRejected);
    assert.doesNotMatch(response, /raw-secret/);
  });
});

test("mms metadata request handler ignores non-mms methods and errors unknown mms methods", async () => {
  assert.equal(handleMMSMetadataRequest(JSON.stringify({ id: "mmschat-1", method: "mmschat/list" }), () => {}), false);

  let response = "";
  let resolveResponse;
  const responsePromise = new Promise((resolve) => {
    resolveResponse = resolve;
  });

  const handled = handleMMSMetadataRequest(
    JSON.stringify({ id: "unknown-1", method: "mms/unknown", params: {} }),
    (payload) => {
      response = payload;
      resolveResponse();
    },
    { config: emptyConfig() }
  );

  assert.equal(handled, true);
  await responsePromise;
  const parsed = JSON.parse(response);
  assert.equal(parsed.error.data.errorCode, MMS_METADATA_ERROR_CODES.unsupportedMethod);
});

function tempMMSConfigWithPresetOverrides(overrides) {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "mms-metadata-hub-preset-"));
  const mmsConfigDir = path.join(rootDir, "mms-config");
  fs.mkdirSync(mmsConfigDir, { recursive: true });

  const presetLines = Object.entries(overrides).map(([id, cfg]) => {
    const body = Object.entries(cfg)
      .map(([k, v]) => `${k} = ${typeof v === "boolean" ? (v ? "true" : "false") : `"${v}"`}`)
      .join("\n");
    return `[presets.${id}]\n${body}\n`;
  }).join("\n");

  fs.writeFileSync(path.join(mmsConfigDir, "config.toml"), `
visible_providers = ["kimi"]

[[providers]]
id = "kimi"
name = "Kimi"
models = ["moonshot-v1"]
default_model = "kimi-k2"
api_key = "sk-live-secret"
auth_secret_ref = "keychain:mms/kimi"
visible = true

[[providers]]
id = "hidden-provider"
name = "Hidden"
models = ["hidden-model"]
default_model = "hidden-model"
token = "hidden-secret"
visible = false

[presets.fast]
provider = "kimi"
model = "kimi-k2"

${presetLines}
`, { mode: 0o600 });

  return {
    mmsConfigDir,
    rootDir,
    cleanup() {
      fs.rmSync(rootDir, { recursive: true, force: true });
    },
  };
}

test("mms/launch/plan rejects preset with hidden=true", () => {
  const ctx = tempMMSConfigWithPresetOverrides({
    "hidden-preset": { provider: "kimi", model: "kimi-k2", hidden: true },
  });
  try {
    const hub = createMMSMetadataHub({ env: { MMS_CONFIG_DIR: ctx.mmsConfigDir } });
    assert.throws(
      () => hub.handleMethod(MMS_METADATA_METHODS.launchPlan, { cwd: "/tmp/x", preset: "hidden-preset" }),
      (err) => err.errorCode === MMS_METADATA_ERROR_CODES.invalidParams
        && err.message.includes("hidden")
    );
  } finally {
    ctx.cleanup();
  }
});

test("mms/launch/plan rejects preset with visible=false", () => {
  const ctx = tempMMSConfigWithPresetOverrides({
    "invisible-preset": { provider: "kimi", model: "kimi-k2", visible: false },
  });
  try {
    const hub = createMMSMetadataHub({ env: { MMS_CONFIG_DIR: ctx.mmsConfigDir } });
    assert.throws(
      () => hub.handleMethod(MMS_METADATA_METHODS.launchPlan, { cwd: "/tmp/x", preset: "invisible-preset" }),
      (err) => err.errorCode === MMS_METADATA_ERROR_CODES.invalidParams
        && err.message.includes("hidden")
    );
  } finally {
    ctx.cleanup();
  }
});

test("mms/launch/plan rejects preset referencing a hidden provider", () => {
  const ctx = tempMMSConfigWithPresetOverrides({
    "hidden-provider-preset": { provider: "hidden-provider", model: "hidden-model" },
  });
  try {
    const hub = createMMSMetadataHub({ env: { MMS_CONFIG_DIR: ctx.mmsConfigDir } });
    assert.throws(
      () => hub.handleMethod(MMS_METADATA_METHODS.launchPlan, { cwd: "/tmp/x", preset: "hidden-provider-preset" }),
      (err) => err.errorCode === MMS_METADATA_ERROR_CODES.invalidParams
        && err.message.includes("hidden")
        && err.message.includes("hidden-provider")
    );
  } finally {
    ctx.cleanup();
  }
});

test("mms/launch/plan visible preset dry-run remains PASS", () => {
  const ctx = tempMMSConfigWithPresetOverrides({});
  try {
    const hub = createMMSMetadataHub({ env: { MMS_CONFIG_DIR: ctx.mmsConfigDir } });
    const result = hub.handleMethod(MMS_METADATA_METHODS.launchPlan, {
      cwd: "/tmp/project-a",
      preset: "fast",
    });
    const serialized = JSON.stringify(result);
    assert.equal(result.dryRun, true);
    assert.equal(result.spawn, false);
    assert.doesNotMatch(serialized, /sk-live-secret|authSecretRef/);
  } finally {
    ctx.cleanup();
  }
});

function withTempMMSConfig(run) {
  const rootDir = fs.mkdtempSync(path.join(os.tmpdir(), "mms-metadata-hub-"));
  const mmsConfigDir = path.join(rootDir, "mms-config");
  fs.mkdirSync(mmsConfigDir, { recursive: true });
  fs.writeFileSync(path.join(mmsConfigDir, "config.toml"), `
visible_providers = ["kimi"]

[[providers]]
id = "kimi"
name = "Kimi"
models = ["moonshot-v1"]
default_model = "kimi-k2"
api_key = "sk-live-secret"
auth_secret_ref = "keychain:mms/kimi"
visible = true

[[providers]]
id = "hidden-provider"
name = "Hidden"
models = ["hidden-model"]
default_model = "hidden-model"
token = "hidden-secret"
visible = false

[presets.fast]
provider = "kimi"
model = "kimi-k2"
credential = "raw-preset-secret"

[presets.hidden]
provider = "hidden-provider"
model = "hidden-model"
`, { mode: 0o600 });

  try {
    return run({ mmsConfigDir, rootDir });
  } finally {
    fs.rmSync(rootDir, { recursive: true, force: true });
  }
}

function emptyConfig() {
  return {
    found: false,
    source: "test",
    configDir: ".",
    providers: [],
    presets: {},
    visibleProviders: [],
  };
}
