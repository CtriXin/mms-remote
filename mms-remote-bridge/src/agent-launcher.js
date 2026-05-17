// FILE: agent-launcher.js
// Purpose: Builds offline MMS agent launch plans using isolated config directories.
// Layer: CLI helper
// Exports: isolated config directory helpers plus dry-run launch plan builders.
// Depends on: crypto, fs, os, path, ./mms-config-reader

const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { readMMSConfig } = require("./mms-config-reader");

const ISOLATED_CONFIG_PREFIX = "mms-agent-config-";
const ISOLATED_CONFIG_MARKER = ".mms-isolated-config";
const SECRET_ENV_MARKERS = ["APIKEY", "API_KEY", "CREDENTIAL", "PASSWORD", "SECRET", "SESSION_ID", "TOKEN"];

function createIsolatedMMSConfigDir({
  configToml = "",
  fsImpl = fs,
  osImpl = os,
  sourceConfigDir = "",
  sourceConfigPath = "",
  tempRoot = "",
} = {}) {
  const root = normalizeOptionalString(tempRoot) || osImpl.tmpdir();
  fsImpl.mkdirSync(root, { recursive: true, mode: 0o700 });
  const configDir = fsImpl.mkdtempSync(path.join(root, ISOLATED_CONFIG_PREFIX));
  const configPath = path.join(configDir, "config.toml");

  if (sourceConfigDir) {
    copyDirectory(sourceConfigDir, configDir, fsImpl);
  } else if (sourceConfigPath) {
    fsImpl.copyFileSync(sourceConfigPath, configPath);
  }

  if (configToml) {
    fsImpl.writeFileSync(configPath, configToml, { mode: 0o600 });
  }

  fsImpl.writeFileSync(path.join(configDir, ISOLATED_CONFIG_MARKER), "created-by-mms-agent-launcher\n", { mode: 0o600 });
  return {
    configDir,
    configPath,
    cleanup: {
      helper: "cleanupIsolatedMMSConfigDir",
      marker: ISOLATED_CONFIG_MARKER,
    },
  };
}

function cleanupIsolatedMMSConfigDir(configDir, { fsImpl = fs } = {}) {
  assertSafeIsolatedConfigDir(configDir, fsImpl);
  fsImpl.rmSync(configDir, { recursive: true, force: true });
  return { cleaned: true, configDir };
}

function buildMMSAgentLaunchPlan({
  agent = "claude",
  config = null,
  configDir = "",
  cwd = "",
  env = {},
  extraArgs = [],
  fsImpl = fs,
  mmsBin = "mms",
  model = "",
  osImpl = os,
  preset = "",
  provider = "",
} = {}) {
  const normalizedConfigDir = requireNonEmptyString(configDir, "configDir");
  const metadata = config || readMMSConfig({
    env: { MMS_CONFIG_DIR: normalizedConfigDir },
    fsImpl,
    osImpl,
  });
  const profile = resolveLaunchProfile({
    agent,
    config: metadata,
    model,
    preset,
    provider,
  });
  const command = normalizeOptionalString(mmsBin) || "mms";
  const argv = buildMMSAgentArgv({
    agent,
    extraArgs,
    model: profile.model,
    preset: profile.preset,
    provider: profile.provider,
  });

  return {
    command,
    argv,
    cwd: normalizeOptionalString(cwd) || process.cwd(),
    env: {
      ...sanitizeLaunchEnv(env),
      MMS_CONFIG_DIR: normalizedConfigDir,
    },
    isolatedConfigDir: normalizedConfigDir,
    profile,
    spawn: false,
    cleanup: {
      helper: "cleanupIsolatedMMSConfigDir",
      configDir: normalizedConfigDir,
    },
  };
}

function buildMMSAgentArgv({ agent = "claude", extraArgs = [], model = "", preset = "", provider = "" } = {}) {
  const argv = [requireNonEmptyString(agent, "agent")];
  if (preset) {
    argv.push("--preset", preset);
  }
  if (provider) {
    argv.push("--provider", provider);
  }
  if (model) {
    argv.push("--model", model);
  }
  return argv.concat(extraArgs.map((arg) => String(arg)));
}

function resolveLaunchProfile({ agent = "claude", config = {}, model = "", preset = "", provider = "" } = {}) {
  const presetName = normalizeOptionalString(preset);
  const presetMetadata = presetName ? config.presets?.[presetName] || {} : {};
  const providerId = normalizeOptionalString(provider || presetMetadata.provider);
  const providerMetadata = findProviderMetadata(config.providers || [], providerId);
  const resolvedModel = normalizeOptionalString(model || presetMetadata.model || providerMetadata.defaultModel);
  const authSecretRef = normalizeOptionalString(presetMetadata.authSecretRef || providerMetadata.authSecretRef);
  const credentialPresent = Boolean(presetMetadata.credentialPresent || providerMetadata.credentialPresent);
  const profile = {
    agent: requireNonEmptyString(agent, "agent"),
    provider: providerId,
    model: resolvedModel,
    preset: presetName,
    launchProfileName: presetName || providerId || "default",
    authSecretRef,
    credentialPresent,
  };
  profile.launchProfileFingerprint = fingerprintLaunchProfile(profile);
  return compactObject(profile);
}

function findProviderMetadata(providers, providerId) {
  if (!providerId) {
    return {};
  }
  return providers.find((provider) => {
    return provider.id === providerId || provider.name === providerId || provider.provider === providerId;
  }) || {};
}

function fingerprintLaunchProfile(profile) {
  const stableProfile = {
    agent: profile.agent || "",
    authSecretRef: profile.authSecretRef || "",
    model: profile.model || "",
    preset: profile.preset || "",
    provider: profile.provider || "",
  };
  const digest = crypto.createHash("sha256").update(JSON.stringify(stableProfile)).digest("hex");
  return `sha256:${digest}`;
}

function copyDirectory(sourceDir, targetDir, fsImpl) {
  fsImpl.mkdirSync(targetDir, { recursive: true, mode: 0o700 });
  for (const entry of fsImpl.readdirSync(sourceDir, { withFileTypes: true })) {
    const sourcePath = path.join(sourceDir, entry.name);
    const targetPath = path.join(targetDir, entry.name);
    if (entry.isDirectory()) {
      copyDirectory(sourcePath, targetPath, fsImpl);
      continue;
    }
    if (entry.isFile()) {
      fsImpl.copyFileSync(sourcePath, targetPath);
    }
  }
}

function assertSafeIsolatedConfigDir(configDir, fsImpl) {
  const normalizedConfigDir = requireNonEmptyString(configDir, "configDir");
  if (!path.basename(normalizedConfigDir).startsWith(ISOLATED_CONFIG_PREFIX)) {
    throw new Error("Refusing to cleanup a non-isolated MMS config dir");
  }
  if (!fsImpl.existsSync(path.join(normalizedConfigDir, ISOLATED_CONFIG_MARKER))) {
    throw new Error("Refusing to cleanup an MMS config dir without an isolation marker");
  }
}

function sanitizeLaunchEnv(env) {
  const safeEnv = {};
  for (const [key, value] of Object.entries(env || {})) {
    if (isSecretEnvKey(key)) {
      continue;
    }
    safeEnv[key] = value;
  }
  return safeEnv;
}

function isSecretEnvKey(key) {
  const normalized = String(key).replace(/[-\s.]/g, "_").toUpperCase();
  return SECRET_ENV_MARKERS.some((marker) => normalized.includes(marker));
}

function compactObject(value) {
  const result = {};
  for (const [key, item] of Object.entries(value)) {
    if (item === undefined || item === "") {
      continue;
    }
    result[key] = item;
  }
  return result;
}

function requireNonEmptyString(value, name) {
  const normalized = normalizeOptionalString(value);
  if (!normalized) {
    throw new Error(`${name} is required`);
  }
  return normalized;
}

function normalizeOptionalString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : "";
}

module.exports = {
  buildMMSAgentArgv,
  buildMMSAgentLaunchPlan,
  cleanupIsolatedMMSConfigDir,
  createIsolatedMMSConfigDir,
  fingerprintLaunchProfile,
  resolveLaunchProfile,
  sanitizeLaunchEnv,
};
