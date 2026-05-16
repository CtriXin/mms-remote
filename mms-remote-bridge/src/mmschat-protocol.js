// FILE: mmschat-protocol.js
// Purpose: Defines MMSChat JSON-RPC method names, schemas, and side-effect-free validators.
// Layer: Protocol helper
// Exports: MMSChat protocol constants and validation helpers
// Depends on: none

const MMSCHAT_METHODS = Object.freeze({
  list: "mmschat/list",
  detail: "mmschat/detail",
  attach: "mmschat/attach",
  send: "mmschat/send",
  resume: "mmschat/resume",
  openVisible: "mmschat/openVisible",
  kill: "mmschat/kill",
  hide: "mmschat/hide",
  clearCache: "mmschat/cache/clear",
});

const MMSCHAT_STATUS = Object.freeze({
  pending: "pending",
  running: "running",
  idle: "idle",
  dead: "dead",
  needsResume: "needs-resume",
  unknown: "unknown",
});

const MMSCHAT_NATIVE_SESSION_STATUS = Object.freeze({
  pending: "pending",
  confirmed: "confirmed",
  unavailable: "unavailable",
});

const MMSCHAT_TRANSCRIPT_CACHE_STATE = Object.freeze({
  empty: "empty",
  stale: "stale",
  fresh: "fresh",
  rawFallback: "raw-fallback",
});

const MMSCHAT_ERROR_CODES = Object.freeze({
  invalidParams: "invalid_params",
  sessionNotFound: "session_not_found",
  nativeSessionPending: "native_session_pending",
  paneDead: "pane_dead",
  busy: "busy",
  sendDisabled: "send_disabled",
  resumeFailed: "resume_failed",
  unsupportedMethod: "unsupported_method",
  secretRejected: "secret_rejected",
});

const MMSCHAT_FEATURES = Object.freeze({
  sendEnabledByDefault: false,
});

const MMSCHAT_METHOD_LIST = Object.freeze(Object.values(MMSCHAT_METHODS));
const MMSCHAT_STATUS_LIST = Object.freeze(Object.values(MMSCHAT_STATUS));

const MMSCHAT_STATUS_TRANSITIONS = Object.freeze({
  [MMSCHAT_STATUS.pending]: Object.freeze([
    MMSCHAT_STATUS.running,
    MMSCHAT_STATUS.unknown,
  ]),
  [MMSCHAT_STATUS.running]: Object.freeze([
    MMSCHAT_STATUS.idle,
    MMSCHAT_STATUS.dead,
    MMSCHAT_STATUS.needsResume,
  ]),
  [MMSCHAT_STATUS.idle]: Object.freeze([
    MMSCHAT_STATUS.running,
    MMSCHAT_STATUS.dead,
    MMSCHAT_STATUS.needsResume,
  ]),
  [MMSCHAT_STATUS.dead]: Object.freeze([
    MMSCHAT_STATUS.needsResume,
  ]),
  [MMSCHAT_STATUS.needsResume]: Object.freeze([
    MMSCHAT_STATUS.pending,
    MMSCHAT_STATUS.running,
  ]),
  [MMSCHAT_STATUS.unknown]: Object.freeze([
    MMSCHAT_STATUS.pending,
    MMSCHAT_STATUS.running,
    MMSCHAT_STATUS.needsResume,
  ]),
});

const MMSCHAT_SESSION_SCHEMA = Object.freeze({
  type: "object",
  additionalProperties: false,
  required: [
    "mmschatId",
    "cwd",
    "agent",
    "status",
    "createdAt",
    "lastActivityAt",
    "hidden",
  ],
  properties: Object.freeze({
    mmschatId: "string",
    nativeClaudeSessionId: "string|null",
    nativeClaudeSessionStatus: "pending|confirmed|unavailable",
    title: "string|null",
    cwd: "string",
    project: "string|null",
    agent: "claude",
    provider: "string|null",
    model: "string|null",
    launchProfileName: "string|null",
    launchProfileFingerprint: "string|null",
    authSecretRef: "string|null",
    tmuxPaneId: "string|null",
    tmuxSessionName: "string|null",
    pid: "integer|null",
    status: "pending|running|idle|dead|needs-resume|unknown",
    createdAt: "date-time",
    lastActivityAt: "date-time",
    lastPreviewText: "string|null",
    hidden: "boolean",
    transcriptCacheState: "empty|stale|fresh|raw-fallback",
    metadata: "object|null",
  }),
});

function isMMSChatMethod(method) {
  return MMSCHAT_METHOD_LIST.includes(method);
}

function isMMSChatStatus(status) {
  return MMSCHAT_STATUS_LIST.includes(status);
}

function canTransitionMMSChatStatus(fromStatus, toStatus) {
  const allowedTargets = MMSCHAT_STATUS_TRANSITIONS[fromStatus];
  return Array.isArray(allowedTargets) && allowedTargets.includes(toStatus);
}

function normalizeMMSChatRequest(rawMessage) {
  let parsed;
  try {
    parsed = JSON.parse(rawMessage);
  } catch {
    return null;
  }

  const method = readString(parsed?.method);
  if (!isMMSChatMethod(method)) {
    return null;
  }

  return {
    id: parsed.id,
    method,
    params: isPlainObject(parsed.params) ? parsed.params : {},
  };
}

function validateMMSChatParams(method, params = {}) {
  switch (method) {
    case MMSCHAT_METHODS.list:
      return validateListParams(params);
    case MMSCHAT_METHODS.detail:
      return requireMMSChatId(params);
    case MMSCHAT_METHODS.attach:
      return validateAttachParams(params);
    case MMSCHAT_METHODS.send:
      return validateSendParams(params);
    case MMSCHAT_METHODS.resume:
      return requireMMSChatId(params);
    case MMSCHAT_METHODS.openVisible:
      return requireMMSChatId(params);
    case MMSCHAT_METHODS.kill:
      return requireMMSChatId(params);
    case MMSCHAT_METHODS.hide:
      return validateHideParams(params);
    case MMSCHAT_METHODS.clearCache:
      return requireMMSChatId(params);
    default:
      return invalidParams("Unsupported MMSChat method.");
  }
}

function buildSendDisabledResult() {
  return {
    accepted: false,
    disabled: true,
    errorCode: MMSCHAT_ERROR_CODES.sendDisabled,
  };
}

function createMMSChatError(errorCode, message) {
  const error = new Error(message);
  error.errorCode = errorCode;
  error.userMessage = message;
  return error;
}

function validateListParams(params) {
  const status = Array.isArray(params.status) ? params.status : [];
  const invalidStatus = status.find((value) => !isMMSChatStatus(value));
  if (invalidStatus) {
    return invalidParams(`Invalid MMSChat status: ${invalidStatus}`);
  }

  return validParams({
    includeHidden: Boolean(params.includeHidden),
    status,
    cwd: readString(params.cwd),
    limit: readPositiveInteger(params.limit),
  });
}

function validateAttachParams(params) {
  const cwd = readString(params.cwd);
  if (!cwd) {
    return invalidParams("mmschat/attach requires cwd.");
  }

  if (containsSecretLikeValue(params)) {
    return invalidParams("mmschat/attach params must not contain raw secrets.", MMSCHAT_ERROR_CODES.secretRejected);
  }

  return validParams({
    cwd,
    tmuxPaneId: readString(params.tmuxPaneId),
    tmuxSessionName: readString(params.tmuxSessionName),
    nativeClaudeSessionId: readString(params.nativeClaudeSessionId),
    provider: readString(params.provider),
    model: readString(params.model),
    launchProfileName: readString(params.launchProfileName),
    launchProfileFingerprint: readString(params.launchProfileFingerprint),
    authSecretRef: readString(params.authSecretRef),
  });
}

function validateSendParams(params) {
  const base = requireMMSChatId(params);
  if (!base.ok) {
    return base;
  }

  const text = readString(params.text);
  if (!text) {
    return invalidParams("mmschat/send requires text.");
  }

  return validParams({
    ...base.value,
    text,
    clientMessageId: readString(params.clientMessageId),
    featureFlag: params.featureFlag === true,
  });
}

function validateHideParams(params) {
  const base = requireMMSChatId(params);
  if (!base.ok) {
    return base;
  }

  return validParams({
    ...base.value,
    hidden: params.hidden !== false,
  });
}

function requireMMSChatId(params) {
  const mmschatId = readString(params.mmschatId);
  if (!mmschatId) {
    return invalidParams("MMSChat request requires mmschatId.");
  }

  return validParams({ mmschatId });
}

function validParams(value) {
  return { ok: true, value };
}

function invalidParams(message, errorCode = MMSCHAT_ERROR_CODES.invalidParams) {
  return { ok: false, errorCode, message };
}

function readString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function readPositiveInteger(value) {
  return Number.isInteger(value) && value > 0 ? value : null;
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function containsSecretLikeValue(params) {
  const forbiddenKeys = ["apiKey", "authToken", "token", "pairingSecret", "sessionId"];
  return Object.keys(params).some((key) => forbiddenKeys.includes(key));
}

module.exports = {
  MMSCHAT_METHODS,
  MMSCHAT_STATUS,
  MMSCHAT_NATIVE_SESSION_STATUS,
  MMSCHAT_TRANSCRIPT_CACHE_STATE,
  MMSCHAT_ERROR_CODES,
  MMSCHAT_FEATURES,
  MMSCHAT_STATUS_TRANSITIONS,
  MMSCHAT_SESSION_SCHEMA,
  isMMSChatMethod,
  isMMSChatStatus,
  canTransitionMMSChatStatus,
  normalizeMMSChatRequest,
  validateMMSChatParams,
  buildSendDisabledResult,
  createMMSChatError,
};
