// FILE: mms-metadata-hub.js
// Purpose: Serves read-only MMS provider/model metadata and dry-run launch plans.
// Layer: Service coordinator
// Exports: MMS metadata hub factory plus JSON-RPC request helpers.
// Depends on: ./mms-config-reader, ./agent-launcher

const { buildMMSAgentLaunchPlan } = require("./agent-launcher");
const { readMMSConfig } = require("./mms-config-reader");

const MMS_METADATA_METHODS = Object.freeze({
  providers: "mms/providers",
  presets: "mms/presets",
  models: "mms/models",
  launchPlan: "mms/launch/plan",
});

const MMS_METADATA_ERROR_CODES = Object.freeze({
  invalidParams: "invalid_params",
  secretRejected: "secret_rejected",
  unsupportedMethod: "unsupported_method",
});

const MMS_METADATA_METHOD_LIST = Object.freeze(Object.values(MMS_METADATA_METHODS));

function createMMSMetadataHub(options = {}) {
  const readConfig = options.readConfig || readMMSConfig;
  const buildLaunchPlan = options.buildLaunchPlan || buildMMSAgentLaunchPlan;

  function readConfigMetadata() {
    if (options.config) {
      return options.config;
    }
    return readConfig({
      env: options.env || process.env,
      fsImpl: options.fsImpl,
      osImpl: options.osImpl,
    });
  }

  return {
    handleMethod(method, params = {}) {
      const config = readConfigMetadata();

      switch (method) {
        case MMS_METADATA_METHODS.providers:
          return {
            providers: listVisibleProviders(config),
            source: config.source || "unknown",
            found: config.found === true,
          };
        case MMS_METADATA_METHODS.presets:
          return {
            presets: listVisiblePresets(config),
            source: config.source || "unknown",
            found: config.found === true,
          };
        case MMS_METADATA_METHODS.models:
          return {
            models: listVisibleModels(config),
            source: config.source || "unknown",
            found: config.found === true,
          };
        case MMS_METADATA_METHODS.launchPlan:
          return buildDryRunLaunchPlan({ buildLaunchPlan, config }, params);
        default:
          throw createMMSMetadataError(
            MMS_METADATA_ERROR_CODES.unsupportedMethod,
            `Unsupported MMS metadata method: ${method}`
          );
      }
    },
  };
}

function listVisibleProviders(config) {
  return getVisibleProviders(config).map((provider) => ({
    id: readOptionalString(provider.id) || "unknown",
    name: readOptionalString(provider.name) || readOptionalString(provider.id) || "Unknown",
    defaultModel: readOptionalString(provider.defaultModel),
    models: listProviderModels(provider),
    visible: true,
    credentialPresent: provider.credentialPresent === true,
  }));
}

function listVisiblePresets(config) {
  const providersById = buildProviderLookup(getVisibleProviders(config));
  return Object.entries(config.presets || {})
    .map(([id, preset]) => buildPresetSummary(id, preset, providersById))
    .filter((preset) => preset.visible);
}

function buildPresetSummary(id, preset = {}, providersById) {
  const providerId = readOptionalString(preset.provider);
  const provider = providerId ? providersById.get(providerId) || null : null;
  const visible = preset.visible !== false && preset.hidden !== true && (!providerId || provider !== null);
  return {
    id,
    provider: providerId,
    model: readOptionalString(preset.model),
    defaultModel: readOptionalString(preset.defaultModel || provider?.defaultModel),
    visible,
    credentialPresent: preset.credentialPresent === true || provider?.credentialPresent === true,
  };
}

function listVisibleModels(config) {
  return getVisibleProviders(config).flatMap((provider) => {
    const providerId = readOptionalString(provider.id) || "unknown";
    const defaultModel = readOptionalString(provider.defaultModel);
    return listProviderModels(provider).map((model) => ({
      id: `${providerId}:${model}`,
      provider: providerId,
      providerName: readOptionalString(provider.name) || providerId,
      model,
      defaultModel,
      isDefault: Boolean(defaultModel && model === defaultModel),
      credentialPresent: provider.credentialPresent === true,
    }));
  });
}

function buildDryRunLaunchPlan({ buildLaunchPlan, config }, params = {}) {
  const launchParams = validateLaunchPlanParams(params, config);
  const plan = buildLaunchPlan({
    agent: "claude",
    config,
    configDir: readOptionalString(config.configDir) || ".",
    cwd: launchParams.cwd,
    model: launchParams.model || "",
    preset: launchParams.preset || "",
    provider: launchParams.provider || "",
  });

  return sanitizeLaunchPlan(plan, config);
}

function validateLaunchPlanParams(params, config) {
  if (!isPlainObject(params)) {
    throw createMMSMetadataError(MMS_METADATA_ERROR_CODES.invalidParams, "mms/launch/plan params must be an object.");
  }
  if (containsSecretLikeParam(params)) {
    throw createMMSMetadataError(
      MMS_METADATA_ERROR_CODES.secretRejected,
      "mms/launch/plan params must not contain raw secrets."
    );
  }

  const cwd = readOptionalString(params.cwd);
  const preset = readOptionalString(params.preset);
  const provider = readOptionalString(params.provider);
  const model = readOptionalString(params.model);

  if (!cwd) {
    throw createMMSMetadataError(MMS_METADATA_ERROR_CODES.invalidParams, "mms/launch/plan requires cwd.");
  }
  if (!preset && (!provider || !model)) {
    throw createMMSMetadataError(
      MMS_METADATA_ERROR_CODES.invalidParams,
      "mms/launch/plan requires preset or provider plus model."
    );
  }
  if (preset && !config.presets?.[preset]) {
    throw createMMSMetadataError(MMS_METADATA_ERROR_CODES.invalidParams, `Unknown MMS preset: ${preset}`);
  }
  if (preset) {
    const presetEntry = config.presets[preset];
    if (presetEntry?.hidden === true || presetEntry?.visible === false) {
      throw createMMSMetadataError(MMS_METADATA_ERROR_CODES.invalidParams, `MMS preset is hidden: ${preset}`);
    }
    const presetProviderId = readOptionalString(presetEntry?.provider);
    if (presetProviderId && !hasVisibleProvider(config, presetProviderId)) {
      throw createMMSMetadataError(
        MMS_METADATA_ERROR_CODES.invalidParams,
        `MMS preset "${preset}" references a hidden or unknown provider: ${presetProviderId}`
      );
    }
  }
  if (provider && !hasVisibleProvider(config, provider)) {
    throw createMMSMetadataError(MMS_METADATA_ERROR_CODES.invalidParams, `Unknown MMS provider: ${provider}`);
  }

  return { cwd, model, preset, provider };
}

function sanitizeLaunchPlan(plan, config) {
  return {
    dryRun: true,
    command: plan.command,
    argv: Array.isArray(plan.argv) ? plan.argv.map(String) : [],
    cwd: plan.cwd,
    spawn: false,
    profile: sanitizeLaunchProfile(plan.profile || {}),
    config: {
      found: config.found === true,
      source: config.source || "unknown",
    },
  };
}

function sanitizeLaunchProfile(profile) {
  return compactObject({
    agent: readOptionalString(profile.agent),
    provider: readOptionalString(profile.provider),
    model: readOptionalString(profile.model),
    preset: readOptionalString(profile.preset),
    launchProfileName: readOptionalString(profile.launchProfileName),
    launchProfileFingerprint: readOptionalString(profile.launchProfileFingerprint),
    credentialPresent: profile.credentialPresent === true,
  });
}

async function handleMMSMetadataMethod(method, params = {}, options = {}) {
  const hub = options.hub || createMMSMetadataHub(options);
  return hub.handleMethod(method, params, options);
}

function handleMMSMetadataRequest(rawMessage, sendResponse, options = {}) {
  const message = normalizeMMSMetadataRequest(rawMessage);
  if (!message) {
    return false;
  }

  handleMMSMetadataMethod(message.method, message.params || {}, options)
    .then((result) => {
      sendResponse(JSON.stringify({ id: message.id ?? null, result }));
    })
    .catch((error) => {
      sendResponse(JSON.stringify({
        id: message.id ?? null,
        error: {
          code: -32000,
          message: error?.message || "MMS metadata request failed",
          data: {
            errorCode: error?.errorCode || MMS_METADATA_ERROR_CODES.unsupportedMethod,
          },
        },
      }));
    });

  return true;
}

function normalizeMMSMetadataRequest(rawMessage) {
  let parsed;
  try {
    parsed = JSON.parse(rawMessage);
  } catch {
    return null;
  }

  const method = readOptionalString(parsed?.method);
  if (!method || !method.startsWith("mms/")) {
    return null;
  }

  return {
    id: parsed.id,
    method,
    params: isPlainObject(parsed.params) ? parsed.params : {},
  };
}

function getVisibleProviders(config) {
  const visibleIds = new Set((config.visibleProviders || []).map(readOptionalString).filter(Boolean));
  return (config.providers || []).filter((provider) => {
    const providerId = readOptionalString(provider.id);
    return provider.visible !== false && (!visibleIds.size || visibleIds.has(providerId));
  });
}

function hasVisibleProvider(config, providerId) {
  return getVisibleProviders(config).some((provider) => {
    return provider.id === providerId || provider.name === providerId || provider.provider === providerId;
  });
}

function buildProviderLookup(providers) {
  const lookup = new Map();
  for (const provider of providers) {
    for (const key of [provider.id, provider.name, provider.provider]) {
      const normalized = readOptionalString(key);
      if (normalized) {
        lookup.set(normalized, provider);
      }
    }
  }
  return lookup;
}

function listProviderModels(provider) {
  const models = Array.isArray(provider.models) ? provider.models.map(readOptionalString).filter(Boolean) : [];
  const defaultModel = readOptionalString(provider.defaultModel);
  return uniqueStrings(defaultModel ? [defaultModel, ...models] : models);
}

function createMMSMetadataError(errorCode, message) {
  const error = new Error(message);
  error.errorCode = errorCode;
  error.userMessage = message;
  return error;
}

function containsSecretLikeParam(params) {
  return Object.keys(params || {}).some((key) => {
    const normalized = key.toLowerCase().replace(/[_-]/g, "");
    return ["apikey", "authtoken", "credential", "password", "secret", "sessionid", "token"].some((marker) => {
      return normalized.includes(marker);
    });
  });
}

function uniqueStrings(values) {
  return Array.from(new Set(values.filter(Boolean)));
}

function compactObject(value) {
  return Object.fromEntries(Object.entries(value).filter(([, entry]) => entry !== undefined && entry !== null));
}

function readOptionalString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

module.exports = {
  MMS_METADATA_ERROR_CODES,
  MMS_METADATA_METHODS,
  MMS_METADATA_METHOD_LIST,
  createMMSMetadataHub,
  handleMMSMetadataMethod,
  handleMMSMetadataRequest,
};
