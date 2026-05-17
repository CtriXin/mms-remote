// FILE: mmschat-launcher.js
// Purpose: Registers offline MMS launch plans as pending MMSChat sessions without starting a process.
// Layer: Service coordinator
// Exports: MMSChat launcher registration helpers.
// Depends on: ./agent-launcher, ./mmschat-registry, ./mmschat-protocol

const {
  buildMMSAgentLaunchPlan,
  resolveLaunchProfile,
} = require("./agent-launcher");
const {
  assertNoPersistedSecrets,
  createMMSChatRegistry,
  createRegistryError,
} = require("./mmschat-registry");
const {
  MMSCHAT_ERROR_CODES,
  MMSCHAT_NATIVE_SESSION_STATUS,
  MMSCHAT_STATUS,
} = require("./mmschat-protocol");

const ALLOWED_NATIVE_SESSION_UPDATE_STATUSES = new Set([
  MMSCHAT_NATIVE_SESSION_STATUS.pending,
  MMSCHAT_NATIVE_SESSION_STATUS.confirmed,
]);

function createMMSChatLauncher(options = {}) {
  const registry = options.registry || createMMSChatRegistry(options.registryOptions || {});
  const buildLaunchPlan = options.buildLaunchPlan || buildMMSAgentLaunchPlan;

  return {
    buildPendingRegistration(input = {}) {
      return buildPendingMMSChatRegistration(input, { buildLaunchPlan });
    },

    registerPendingLaunch(input = {}) {
      return registerPendingMMSChatLaunch(input, { registry, buildLaunchPlan });
    },

    updateNativeClaudeSession(input = {}) {
      return updateMMSChatNativeClaudeSession(input, { registry });
    },
  };
}

function registerPendingMMSChatLaunch(input = {}, options = {}) {
  const registry = options.registry || createMMSChatRegistry(options.registryOptions || {});
  const registration = buildPendingMMSChatRegistration(input, options);
  return registry.register(registration);
}

function buildPendingMMSChatRegistration(input = {}, options = {}) {
  const buildLaunchPlan = options.buildLaunchPlan || buildMMSAgentLaunchPlan;
  const launchPlan = resolveOfflineLaunchPlan(input, buildLaunchPlan);
  const profile = resolveRegistrationProfile(input, launchPlan);
  const nativeSession = buildNativeClaudeSessionFields(input);

  const registration = compactObject({
    mmschatId: readOptionalString(input.mmschatId),
    title: readOptionalString(input.title),
    project: readOptionalString(input.project),
    cwd: readRequiredString(input.cwd || launchPlan.cwd, "MMSChat launcher registration requires cwd."),
    agent: readOptionalString(profile.agent || input.agent) || "claude",
    provider: readOptionalString(profile.provider),
    model: readOptionalString(profile.model),
    launchProfileName: readOptionalString(profile.launchProfileName),
    launchProfileFingerprint: readOptionalString(profile.launchProfileFingerprint),
    authSecretRef: readOptionalString(profile.authSecretRef),
    tmuxPaneId: readOptionalString(readInputOrPlanField(input, launchPlan, "tmuxPaneId")),
    tmuxSessionName: readOptionalString(readInputOrPlanField(input, launchPlan, "tmuxSessionName")),
    pid: normalizePid(readInputOrPlanField(input, launchPlan, "pid")),
    status: MMSCHAT_STATUS.pending,
    nativeClaudeSessionId: nativeSession.nativeClaudeSessionId,
    nativeClaudeSessionStatus: nativeSession.nativeClaudeSessionStatus,
  });

  assertNoPersistedSecrets(registration);
  return registration;
}

function updateMMSChatNativeClaudeSession(input = {}, options = {}) {
  const registry = options.registry || createMMSChatRegistry(options.registryOptions || {});
  const mmschatId = readRequiredString(input.mmschatId, "MMSChat native session update requires mmschatId.");
  const patch = buildExplicitNativeClaudeSessionPatch(input);

  assertNoPersistedSecrets(patch);
  return registry.update(mmschatId, patch);
}

function resolveOfflineLaunchPlan(input, buildLaunchPlan) {
  if (typeof buildLaunchPlan !== "function") {
    throw createInvalidParamsError("MMSChat launcher requires a launch plan builder.");
  }

  const launchPlan = isPlainObject(input.launchPlan)
    ? input.launchPlan
    : buildLaunchPlan(input);

  if (!isPlainObject(launchPlan)) {
    throw createInvalidParamsError("MMSChat launcher requires an offline launch plan.");
  }

  if (launchPlan.spawn !== false) {
    throw createInvalidParamsError("MMSChat launcher only accepts no-spawn launch plans.");
  }

  assertNoPersistedSecrets(launchPlan);
  return launchPlan;
}

function resolveRegistrationProfile(input, launchPlan) {
  const launchProfile = isPlainObject(launchPlan.profile) ? launchPlan.profile : {};
  const resolvedProfile = resolveLaunchProfile({
    agent: launchProfile.agent || input.agent || "claude",
    config: isPlainObject(input.config) ? input.config : {},
    model: launchProfile.model || input.model,
    preset: launchProfile.preset || input.preset,
    provider: launchProfile.provider || input.provider,
  });

  return {
    ...resolvedProfile,
    ...launchProfile,
  };
}

function buildNativeClaudeSessionFields(input) {
  const nativeClaudeSessionId = readOptionalString(input.nativeClaudeSessionId);
  const requestedStatus = Object.prototype.hasOwnProperty.call(input, "nativeClaudeSessionStatus")
    ? normalizeNativeSessionUpdateStatus(input.nativeClaudeSessionStatus)
    : nativeClaudeSessionId
      ? MMSCHAT_NATIVE_SESSION_STATUS.confirmed
      : MMSCHAT_NATIVE_SESSION_STATUS.pending;

  if (requestedStatus === MMSCHAT_NATIVE_SESSION_STATUS.confirmed && !nativeClaudeSessionId) {
    throw createInvalidParamsError("Confirmed native Claude session updates require nativeClaudeSessionId.");
  }

  return {
    nativeClaudeSessionId,
    nativeClaudeSessionStatus: requestedStatus,
  };
}

function buildExplicitNativeClaudeSessionPatch(input) {
  const hasNativeSessionId = Object.prototype.hasOwnProperty.call(input, "nativeClaudeSessionId");
  const hasNativeSessionStatus = Object.prototype.hasOwnProperty.call(input, "nativeClaudeSessionStatus");

  if (!hasNativeSessionId && !hasNativeSessionStatus) {
    throw createInvalidParamsError("Native Claude session update requires explicit session id or status.");
  }

  const nativeClaudeSessionId = hasNativeSessionId
    ? readOptionalString(input.nativeClaudeSessionId)
    : null;
  const nativeClaudeSessionStatus = hasNativeSessionStatus
    ? normalizeNativeSessionUpdateStatus(input.nativeClaudeSessionStatus)
    : nativeClaudeSessionId
      ? MMSCHAT_NATIVE_SESSION_STATUS.confirmed
      : MMSCHAT_NATIVE_SESSION_STATUS.pending;

  if (nativeClaudeSessionStatus === MMSCHAT_NATIVE_SESSION_STATUS.confirmed && !nativeClaudeSessionId) {
    throw createInvalidParamsError("Confirmed native Claude session updates require nativeClaudeSessionId.");
  }

  return compactObject({
    nativeClaudeSessionId: hasNativeSessionId ? nativeClaudeSessionId : undefined,
    nativeClaudeSessionStatus,
  });
}

function normalizeNativeSessionUpdateStatus(value) {
  const status = readRequiredString(value, "Native Claude session status is required.");
  if (!ALLOWED_NATIVE_SESSION_UPDATE_STATUSES.has(status)) {
    throw createInvalidParamsError(`Unsupported native Claude session update status: ${status}`);
  }
  return status;
}

function readInputOrPlanField(input, launchPlan, field) {
  return Object.prototype.hasOwnProperty.call(input, field) ? input[field] : launchPlan[field];
}

function normalizePid(value) {
  return Number.isInteger(value) && value > 0 ? value : null;
}

function compactObject(value) {
  const result = {};
  for (const [key, item] of Object.entries(value)) {
    if (item === undefined || item === null || item === "") {
      continue;
    }
    result[key] = item;
  }
  return result;
}

function readOptionalString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function readRequiredString(value, message) {
  const stringValue = readOptionalString(value);
  if (!stringValue) {
    throw createInvalidParamsError(message);
  }
  return stringValue;
}

function createInvalidParamsError(message) {
  return createRegistryError(MMSCHAT_ERROR_CODES.invalidParams, message);
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

module.exports = {
  buildPendingMMSChatRegistration,
  createMMSChatLauncher,
  registerPendingMMSChatLaunch,
  updateMMSChatNativeClaudeSession,
};
