// FILE: mms-config-reader.js
// Purpose: Reads sanitized MMS provider/preset launch metadata from local config.toml files.
// Layer: CLI helper
// Exports: MMS config path, TOML parsing, and redacted metadata helpers.
// Depends on: fs, os, path

const fs = require("fs");
const os = require("os");
const path = require("path");

const MMS_CONFIG_FILE = "config.toml";
const SECRET_REF_KEYS = new Set([
  "authsecretref",
  "credentialref",
  "keychainref",
  "secretref",
]);
const SECRET_KEY_MARKERS = [
  "apikey",
  "apiKey",
  "credential",
  "password",
  "secret",
  "sessionid",
  "token",
];

function resolveMMSConfigCandidates({ env = process.env, osImpl = os } = {}) {
  const candidates = [];
  const mmsConfigDir = normalizeOptionalString(env.MMS_CONFIG_DIR);
  const xdgConfigHome = normalizeOptionalString(env.XDG_CONFIG_HOME);

  if (mmsConfigDir) {
    candidates.push({
      source: "MMS_CONFIG_DIR",
      configDir: mmsConfigDir,
      configPath: path.join(mmsConfigDir, MMS_CONFIG_FILE),
    });
  }

  if (xdgConfigHome) {
    candidates.push({
      source: "XDG_CONFIG_HOME",
      configDir: path.join(xdgConfigHome, "mms"),
      configPath: path.join(xdgConfigHome, "mms", MMS_CONFIG_FILE),
    });
  }

  const homeConfigDir = path.join(osImpl.homedir(), ".config", "mms");
  candidates.push({
    source: "HOME",
    configDir: homeConfigDir,
    configPath: path.join(homeConfigDir, MMS_CONFIG_FILE),
  });

  return candidates;
}

function resolveMMSConfigPath(options = {}) {
  return resolveMMSConfigCandidates(options)[0].configPath;
}

function readMMSConfig({ fsImpl = fs, ...options } = {}) {
  const candidate = resolveMMSConfigCandidates(options).find((entry) => fsImpl.existsSync(entry.configPath))
    || resolveMMSConfigCandidates(options)[0];

  if (!fsImpl.existsSync(candidate.configPath)) {
    return createEmptyConfigMetadata(candidate);
  }

  const parsed = parseMMSConfigToml(fsImpl.readFileSync(candidate.configPath, "utf8"));
  return buildMMSConfigMetadata(parsed, {
    configDir: candidate.configDir,
    configPath: candidate.configPath,
    source: candidate.source,
  });
}

function parseMMSConfigToml(source) {
  const root = {};
  let current = root;

  for (const rawLine of String(source).split(/\r?\n/)) {
    const line = stripTomlComment(rawLine).trim();
    if (!line) {
      continue;
    }

    const arrayTableMatch = line.match(/^\[\[(.+)\]\]$/);
    if (arrayTableMatch) {
      current = appendArrayTable(root, splitTomlPath(arrayTableMatch[1].trim()));
      continue;
    }

    const tableMatch = line.match(/^\[(.+)\]$/);
    if (tableMatch) {
      current = ensureTable(root, splitTomlPath(tableMatch[1].trim()));
      continue;
    }

    const separatorIndex = findTomlAssignment(line);
    if (separatorIndex < 0) {
      throw new Error(`Unsupported TOML line: ${rawLine}`);
    }

    const keyPath = splitTomlPath(line.slice(0, separatorIndex).trim());
    const value = parseTomlValue(line.slice(separatorIndex + 1).trim());
    setPathValue(current, keyPath, value);
  }

  return root;
}

function buildMMSConfigMetadata(parsedConfig = {}, options = {}) {
  const providers = normalizeProviders(parsedConfig.providers);
  const presets = normalizeNamedMetadata(parsedConfig.presets || {});
  const overlays = normalizeNamedMetadata(parsedConfig.overlays || {});
  const rootMetadata = sanitizeMetadataObject(parsedConfig, new Set(["providers", "presets", "overlays"]));

  return {
    found: true,
    source: normalizeOptionalString(options.source),
    configPath: normalizeOptionalString(options.configPath),
    configDir: normalizeOptionalString(options.configDir),
    providers,
    presets,
    overlays,
    visibleProviders: resolveVisibleProviders(parsedConfig, providers),
    visibleCliIds: resolveVisibleCliIds(parsedConfig, providers),
    metadata: rootMetadata.metadata,
  };
}

function createEmptyConfigMetadata(candidate) {
  return {
    found: false,
    source: candidate.source,
    configPath: candidate.configPath,
    configDir: candidate.configDir,
    providers: [],
    presets: {},
    overlays: {},
    visibleProviders: [],
    visibleCliIds: [],
    metadata: {},
  };
}

function normalizeProviders(value) {
  if (!Array.isArray(value)) {
    return [];
  }

  return value.map((provider, index) => {
    const sanitized = sanitizeMetadataObject(provider || {});
    const metadata = sanitized.metadata;
    const id = normalizeOptionalString(metadata.id || metadata.name || metadata.provider || `provider_${index + 1}`);
    const result = {
      ...metadata,
      id,
      visible: metadata.visible !== false && metadata.hidden !== true,
    };

    if (sanitized.authSecretRef) {
      result.authSecretRef = sanitized.authSecretRef;
    }
    if (sanitized.credentialPresent) {
      result.credentialPresent = true;
    }
    return result;
  });
}

function normalizeNamedMetadata(value) {
  if (!isPlainObject(value)) {
    return {};
  }

  const result = {};
  for (const [name, metadataValue] of Object.entries(value)) {
    const sanitized = sanitizeMetadataObject(metadataValue || {});
    result[name] = {
      ...sanitized.metadata,
      name,
    };
    if (sanitized.authSecretRef) {
      result[name].authSecretRef = sanitized.authSecretRef;
    }
    if (sanitized.credentialPresent) {
      result[name].credentialPresent = true;
    }
  }
  return result;
}

function resolveVisibleProviders(parsedConfig, providers) {
  const configured = toStringArray(
    parsedConfig.visibleProviders
      || parsedConfig.visible_providers
      || parsedConfig.visibleProviderIds
      || parsedConfig.visible_provider_ids
  );
  const providerIds = providers
    .filter((provider) => provider.visible !== false)
    .map((provider) => provider.id)
    .filter(Boolean);
  return uniqueStrings([...configured, ...providerIds]);
}

function resolveVisibleCliIds(parsedConfig, providers) {
  const configured = toStringArray(
    parsedConfig.visibleCliIds
      || parsedConfig.visible_cli_ids
      || parsedConfig.visibleClis
      || parsedConfig.visible_clis
  );
  const cliIds = providers
    .filter((provider) => provider.visible !== false)
    .map((provider) => provider.cli || provider.cliId || provider.command)
    .filter(Boolean);
  return uniqueStrings([...configured, ...cliIds]);
}

function sanitizeMetadataObject(value, skipKeys = new Set()) {
  const output = {};
  let credentialPresent = false;
  let authSecretRef = "";

  for (const [key, item] of Object.entries(value || {})) {
    if (skipKeys.has(key)) {
      continue;
    }

    const safeKey = camelizeTomlKey(key);
    if (isSecretRefKey(key)) {
      authSecretRef = authSecretRef || normalizeSecretRef(item);
      continue;
    }
    if (isSecretMaterialKey(key)) {
      credentialPresent = credentialPresent || hasPresentValue(item);
      continue;
    }

    if (Array.isArray(item)) {
      output[safeKey] = item.map((entry) => sanitizeMetadataValue(entry)).filter((entry) => entry !== undefined);
      continue;
    }
    if (isPlainObject(item)) {
      const nested = sanitizeMetadataObject(item);
      output[safeKey] = nested.metadata;
      credentialPresent = credentialPresent || nested.credentialPresent;
      authSecretRef = authSecretRef || nested.authSecretRef;
      continue;
    }
    output[safeKey] = sanitizeMetadataValue(item);
  }

  return {
    authSecretRef,
    credentialPresent,
    metadata: compactObject(output),
  };
}

function sanitizeMetadataValue(value) {
  if (Array.isArray(value)) {
    return value.map((entry) => sanitizeMetadataValue(entry)).filter((entry) => entry !== undefined);
  }
  if (isPlainObject(value)) {
    return sanitizeMetadataObject(value).metadata;
  }
  if (["boolean", "number", "string"].includes(typeof value)) {
    return value;
  }
  return undefined;
}

function stripTomlComment(line) {
  let quote = "";
  let escaped = false;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (quote) {
      if (quote === '"' && char === "\\" && !escaped) {
        escaped = true;
        continue;
      }
      if (char === quote && !escaped) {
        quote = "";
      }
      escaped = false;
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }
    if (char === "#") {
      return line.slice(0, index);
    }
  }
  return line;
}

function findTomlAssignment(line) {
  let quote = "";
  let bracketDepth = 0;
  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    if (quote) {
      if (char === quote && line[index - 1] !== "\\") {
        quote = "";
      }
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }
    if (char === "[") {
      bracketDepth += 1;
      continue;
    }
    if (char === "]") {
      bracketDepth -= 1;
      continue;
    }
    if (char === "=" && bracketDepth === 0) {
      return index;
    }
  }
  return -1;
}

function parseTomlValue(rawValue) {
  const value = rawValue.trim();
  if (value.startsWith('"') && value.endsWith('"')) {
    return parseDoubleQuotedTomlString(value);
  }
  if (value.startsWith("'") && value.endsWith("'")) {
    return value.slice(1, -1);
  }
  if (value.startsWith("[") && value.endsWith("]")) {
    const body = value.slice(1, -1).trim();
    if (!body) {
      return [];
    }
    return splitTomlList(body).map((entry) => parseTomlValue(entry));
  }
  if (value === "true") {
    return true;
  }
  if (value === "false") {
    return false;
  }
  if (/^[+-]?\d+(?:\.\d+)?$/.test(value)) {
    return Number(value);
  }
  return value;
}

function parseDoubleQuotedTomlString(value) {
  return value
    .slice(1, -1)
    .replace(/\\n/g, "\n")
    .replace(/\\r/g, "\r")
    .replace(/\\t/g, "\t")
    .replace(/\\"/g, '"')
    .replace(/\\\\/g, "\\");
}

function splitTomlList(value) {
  const entries = [];
  let quote = "";
  let bracketDepth = 0;
  let start = 0;

  for (let index = 0; index < value.length; index += 1) {
    const char = value[index];
    if (quote) {
      if (char === quote && value[index - 1] !== "\\") {
        quote = "";
      }
      continue;
    }
    if (char === '"' || char === "'") {
      quote = char;
      continue;
    }
    if (char === "[") {
      bracketDepth += 1;
      continue;
    }
    if (char === "]") {
      bracketDepth -= 1;
      continue;
    }
    if (char === "," && bracketDepth === 0) {
      entries.push(value.slice(start, index).trim());
      start = index + 1;
    }
  }

  entries.push(value.slice(start).trim());
  return entries.filter(Boolean);
}

function splitTomlPath(value) {
  return splitTomlList(value.replace(/\./g, ","))
    .map((part) => parseBareTomlKey(part.trim()))
    .filter(Boolean);
}

function parseBareTomlKey(value) {
  if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
    return parseTomlValue(value);
  }
  return value;
}

function appendArrayTable(root, keyPath) {
  const parent = ensureTable(root, keyPath.slice(0, -1));
  const key = keyPath[keyPath.length - 1];
  if (!Array.isArray(parent[key])) {
    parent[key] = [];
  }
  const next = {};
  parent[key].push(next);
  return next;
}

function ensureTable(root, keyPath) {
  let target = root;
  for (const key of keyPath) {
    if (!isPlainObject(target[key])) {
      target[key] = {};
    }
    target = target[key];
  }
  return target;
}

function setPathValue(target, keyPath, value) {
  const parent = ensureTable(target, keyPath.slice(0, -1));
  parent[keyPath[keyPath.length - 1]] = value;
}

function isSecretRefKey(key) {
  return SECRET_REF_KEYS.has(normalizeSecretKey(key));
}

function isSecretMaterialKey(key) {
  const normalized = normalizeSecretKey(key);
  if (SECRET_REF_KEYS.has(normalized)) {
    return false;
  }
  return SECRET_KEY_MARKERS.some((marker) => normalized.includes(marker.toLowerCase()));
}

function normalizeSecretKey(key) {
  return String(key).replace(/[-_\s.]/g, "").toLowerCase();
}

function normalizeSecretRef(value) {
  return typeof value === "string" && value.trim() ? value.trim() : "";
}

function hasPresentValue(value) {
  if (Array.isArray(value)) {
    return value.length > 0;
  }
  if (isPlainObject(value)) {
    return Object.keys(value).length > 0;
  }
  return value !== undefined && value !== null && value !== "" && value !== false;
}

function toStringArray(value) {
  if (!Array.isArray(value)) {
    return [];
  }
  return value.map((entry) => normalizeOptionalString(entry)).filter(Boolean);
}

function uniqueStrings(values) {
  return [...new Set(values.map((value) => normalizeOptionalString(value)).filter(Boolean))];
}

function camelizeTomlKey(key) {
  return String(key).replace(/[_-]([a-zA-Z0-9])/g, (_, char) => char.toUpperCase());
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

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function normalizeOptionalString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : "";
}

module.exports = {
  buildMMSConfigMetadata,
  parseMMSConfigToml,
  readMMSConfig,
  resolveMMSConfigCandidates,
  resolveMMSConfigPath,
};
