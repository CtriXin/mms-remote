// FILE: mmschat-hub.js
// Purpose: Handles safe bridge-side MMSChat JSON-RPC without live sends, resume, or process mutation.
// Layer: Service coordinator
// Exports: MMSChat hub factory plus JSON-RPC request helpers.
// Depends on: fs, ./mmschat-launcher, ./mmschat-registry, ./mmschat-profile, ./mmschat-protocol, ./mmschat-transcript

const fs = require("fs");
const { seedMMSChatDemoFixtures } = require("./mmschat-demo-fixtures");
const { createMMSChatLauncher } = require("./mmschat-launcher");
const { createMMSChatRegistry } = require("./mmschat-registry");
const {
  compareMMSChatProfiles,
  summarizeMMSChatProfile,
} = require("./mmschat-profile");
const {
  MMSCHAT_ERROR_CODES,
  MMSCHAT_METHODS,
  MMSCHAT_TRANSCRIPT_CACHE_STATE,
  buildSendDisabledResult,
  createMMSChatError,
  normalizeMMSChatRequest,
  validateMMSChatParams,
} = require("./mmschat-protocol");
const {
  readMMSChatTranscriptCache,
  readNativeClaudeTranscriptSnapshot,
  resolveMMSChatTranscriptCachePath,
  writeMMSChatTranscriptCache,
} = require("./mmschat-transcript");

function createMMSChatHub(options = {}) {
  const registry = options.registry || createMMSChatRegistry(options.registryOptions || options);
  const launcher = options.launcher || createMMSChatLauncher({
    registry,
    ...(options.launcherOptions || {}),
  });
  const fsImpl = options.fsImpl || fs;
  const transcriptOptions = options.transcriptOptions || {};
  const readTranscriptCache = options.readTranscriptCache || readMMSChatTranscriptCache;
  const readTranscriptSnapshot = options.readTranscriptSnapshot || readNativeClaudeTranscriptSnapshot;
  const writeTranscriptCache = options.writeTranscriptCache || writeMMSChatTranscriptCache;
  const seedDemoFixtures = options.seedDemoFixtures || seedMMSChatDemoFixtures;

  return {
    launcher,
    registry,

    async handleMethod(method, params = {}) {
      const validated = validateMMSChatParams(method, params);
      if (!validated.ok) {
        throw createMMSChatError(validated.errorCode, validated.message);
      }

      switch (method) {
        case MMSCHAT_METHODS.list:
          return {
            sessions: registry.list(validated.value),
            source: "registry",
            sortedBy: "lastActivityAt",
          };
        case MMSCHAT_METHODS.detail:
          return readSessionDetail({
            readTranscriptCache,
            readTranscriptSnapshot,
            registry,
            transcriptOptions,
            writeTranscriptCache,
          }, validated.value);
        case MMSCHAT_METHODS.attach:
          return attachSession({ launcher, registry }, {
            ...validated.value,
            mmschatId: readOptionalString(params.mmschatId),
          });
        case MMSCHAT_METHODS.hide:
          return {
            session: registry.hide(validated.value.mmschatId, validated.value.hidden),
          };
        case MMSCHAT_METHODS.clearCache:
          return clearSessionCache({ fsImpl, registry, transcriptOptions }, validated.value);
        case MMSCHAT_METHODS.demoSeed:
          return seedDemoFixtures({ registry, transcriptOptions, writeTranscriptCache }, validated.value);
        case MMSCHAT_METHODS.send:
          return buildSendDisabledResult();
        case MMSCHAT_METHODS.resume:
        case MMSCHAT_METHODS.openVisible:
        case MMSCHAT_METHODS.kill:
          throw createMMSChatError(
            MMSCHAT_ERROR_CODES.unsupportedMethod,
            `MMSChat live action is disabled in the safe backend slice: ${method}`
          );
        default:
          throw createMMSChatError(
            MMSCHAT_ERROR_CODES.unsupportedMethod,
            `Unsupported MMSChat method: ${method}`
          );
      }
    },
  };
}

function readSessionDetail(deps, params) {
  const session = getSessionOrThrow(deps.registry, params.mmschatId);
  const cachedTranscript = deps.readTranscriptCache(buildTranscriptCacheOptions(session, deps.transcriptOptions))?.transcript || null;
  if (cachedTranscript) {
    return buildDetailResult(syncSessionTranscriptState(deps.registry, session, cachedTranscript), cachedTranscript);
  }

  const transcript = deps.readTranscriptSnapshot({
    ...deps.transcriptOptions,
    cwd: session.cwd,
    mmschatId: session.mmschatId,
    nativeClaudeSessionId: session.nativeClaudeSessionId,
    rawPreviewText: session.lastPreviewText,
  });

  if (hasTranscriptPayload(transcript)) {
    deps.writeTranscriptCache(transcript, buildTranscriptCacheOptions(session, deps.transcriptOptions));
  }

  return buildDetailResult(syncSessionTranscriptState(deps.registry, session, transcript), transcript);
}

function attachSession(deps, params) {
  const previousSession = findAttachTarget(deps.registry, params);
  const session = deps.launcher.registerPendingLaunch({
    ...params,
    launchPlan: buildAttachLaunchPlan(params),
  });

  return {
    session,
    attached: true,
    profileSummary: summarizeMMSChatProfile(session),
    profileComparison: compareMMSChatProfiles({
      lastKnown: toComparableProfile(previousSession),
      current: toComparableProfile(session),
    }),
  };
}

function clearSessionCache({ fsImpl, registry, transcriptOptions }, params) {
  const session = getSessionOrThrow(registry, params.mmschatId);
  const cachePath = resolveMMSChatTranscriptCachePath(buildTranscriptCacheOptions(session, transcriptOptions));
  fsImpl.rmSync(cachePath, { force: true });
  return {
    session: registry.clearCache(session.mmschatId),
    cacheCleared: true,
  };
}

function buildDetailResult(session, transcript) {
  return {
    session,
    transcript,
    profileSummary: summarizeMMSChatProfile(session),
  };
}

function buildAttachLaunchPlan(params) {
  return {
    cwd: params.cwd,
    spawn: false,
    profile: compactObject({
      agent: "claude",
      authSecretRef: readOptionalString(params.authSecretRef),
      launchProfileFingerprint: readOptionalString(params.launchProfileFingerprint),
      launchProfileName: readOptionalString(params.launchProfileName),
      model: readOptionalString(params.model),
      provider: readOptionalString(params.provider),
    }),
  };
}

function buildTranscriptCacheOptions(session, transcriptOptions) {
  return {
    ...transcriptOptions,
    mmschatId: session.mmschatId,
  };
}

function findAttachTarget(registry, params) {
  if (params.mmschatId) {
    return registry.getById(params.mmschatId);
  }
  if (params.nativeClaudeSessionId) {
    return registry.getByNativeClaudeSessionId(params.nativeClaudeSessionId);
  }
  return null;
}

function getSessionOrThrow(registry, mmschatId) {
  const session = registry.getById(mmschatId);
  if (session) {
    return session;
  }

  throw createMMSChatError(
    MMSCHAT_ERROR_CODES.sessionNotFound,
    `Unknown MMSChat session: ${String(mmschatId || "")}`
  );
}

function hasTranscriptPayload(transcript) {
  return Array.isArray(transcript?.messages) && transcript.messages.length > 0
    || readOptionalString(transcript?.rawPreviewText) !== null;
}

function syncSessionTranscriptState(registry, session, transcript) {
  const nextState = deriveTranscriptCacheState(transcript);
  if (session.transcriptCacheState === nextState) {
    return session;
  }

  return registry.update(session.mmschatId, {
    transcriptCacheState: nextState,
  });
}

function deriveTranscriptCacheState(transcript) {
  if (Array.isArray(transcript?.messages) && transcript.messages.length > 0) {
    return MMSCHAT_TRANSCRIPT_CACHE_STATE.fresh;
  }
  if (readOptionalString(transcript?.rawPreviewText) !== null) {
    return MMSCHAT_TRANSCRIPT_CACHE_STATE.rawFallback;
  }
  return MMSCHAT_TRANSCRIPT_CACHE_STATE.empty;
}

function toComparableProfile(value) {
  if (!value) {
    return null;
  }

  return {
    authSecretRef: readOptionalString(value.authSecretRef),
    credentialPresent: value.credentialPresent === true,
    launchProfileFingerprint: readOptionalString(value.launchProfileFingerprint),
    launchProfileName: readOptionalString(value.launchProfileName),
    model: readOptionalString(value.model),
    provider: readOptionalString(value.provider),
  };
}

async function handleMMSChatMethod(method, params = {}, options = {}) {
  const hub = options.hub || createMMSChatHub(options);
  return hub.handleMethod(method, params, options);
}

function handleMMSChatRequest(rawMessage, sendResponse, options = {}) {
  const message = normalizeMMSChatRequest(rawMessage);
  if (!message) {
    return false;
  }

  handleMMSChatMethod(message.method, message.params || {}, options)
    .then((result) => {
      sendResponse(JSON.stringify({ id: message.id ?? null, result }));
    })
    .catch((error) => {
      sendResponse(JSON.stringify({
        id: message.id ?? null,
        error: {
          code: -32000,
          message: error?.message || "MMSChat request failed",
          data: {
            errorCode: error?.errorCode || MMSCHAT_ERROR_CODES.unsupportedMethod,
          },
        },
      }));
    });

  return true;
}

function compactObject(value) {
  return Object.fromEntries(Object.entries(value).filter(([, entry]) => entry !== undefined));
}

function readOptionalString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

module.exports = {
  createMMSChatHub,
  handleMMSChatMethod,
  handleMMSChatRequest,
};
