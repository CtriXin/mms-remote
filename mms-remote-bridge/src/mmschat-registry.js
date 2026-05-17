// FILE: mmschat-registry.js
// Purpose: Tracks MMSChat session metadata without persisting native Claude transcripts or credentials.
// Layer: Service coordinator
// Exports: Registry CRUD helpers plus a liveness transition helper for MMSChat sessions.
// Depends on: crypto, ./mmschat-protocol, ./mmschat-store

const crypto = require("crypto");
const {
  MMSCHAT_ERROR_CODES,
  MMSCHAT_NATIVE_SESSION_STATUS,
  MMSCHAT_STATUS,
  MMSCHAT_TRANSCRIPT_CACHE_STATE,
  canTransitionMMSChatStatus,
} = require("./mmschat-protocol");
const { createMMSChatStore } = require("./mmschat-store");

const SESSION_FIELDS = Object.freeze([
  "mmschatId",
  "nativeClaudeSessionId",
  "nativeClaudeSessionStatus",
  "title",
  "cwd",
  "project",
  "agent",
  "provider",
  "model",
  "launchProfileName",
  "launchProfileFingerprint",
  "authSecretRef",
  "tmuxPaneId",
  "tmuxSessionName",
  "pid",
  "status",
  "createdAt",
  "lastActivityAt",
  "lastPreviewText",
  "hidden",
  "transcriptCacheState",
  "metadata",
]);

function createMMSChatRegistry(options = {}) {
  const store = options.store || createMMSChatStore(options.storeOptions || options);
  const now = options.now || (() => Date.now());
  const generateId = options.generateId || defaultGenerateId;

  return {
    register(input = {}) {
      assertNoPersistedSecrets(input);
      const state = store.readState();
      const existingIndex = findExistingSessionIndex(state.sessions, input);
      const existingSession = existingIndex >= 0 ? state.sessions[existingIndex] : null;
      const nextSession = existingSession
        ? mergeSessionRecord(existingSession, input, { now, generateId, mode: "register" })
        : createSessionRecord(input, { now, generateId });
      const nextSessions = upsertSession(state.sessions, nextSession, existingIndex);
      store.writeState({ ...state, sessions: nextSessions });
      return cloneJsonValue(nextSession);
    },

    update(sessionOrId, patch = {}) {
      const updateInput = normalizeUpdateInput(sessionOrId, patch);
      assertNoPersistedSecrets(updateInput.patch);
      return mutateById(store, updateInput.mmschatId, now, (session) => {
        return mergeSessionRecord(session, updateInput.patch, {
          now,
          generateId,
          mode: "update",
        });
      });
    },

    list(filters = {}) {
      return listSessions(store.readState().sessions, filters).map((session) => cloneJsonValue(session));
    },

    hide(mmschatId, hidden = true) {
      return mutateById(store, mmschatId, now, (session) => {
        return mergeSessionRecord(session, { hidden }, {
          now,
          generateId,
          mode: "update",
        });
      });
    },

    clearCache(mmschatId) {
      return mutateById(store, mmschatId, now, (session) => {
        return mergeSessionRecord(session, {
          lastPreviewText: null,
          transcriptCacheState: MMSCHAT_TRANSCRIPT_CACHE_STATE.empty,
        }, {
          now,
          generateId,
          mode: "update",
        });
      });
    },

    getById(mmschatId) {
      return cloneOrNull(findSessionById(store.readState().sessions, mmschatId));
    },

    getByNativeClaudeSessionId(nativeClaudeSessionId) {
      return cloneOrNull(findSessionByNativeClaudeSessionId(store.readState().sessions, nativeClaudeSessionId));
    },

    applyLiveness(mmschatId, observation = {}) {
      return mutateById(store, mmschatId, now, (session) => {
        return applyLivenessTransition(session, observation, { now });
      });
    },
  };
}

function applyLivenessTransition(session, observation = {}, { now = () => Date.now() } = {}) {
  const nextStatus = resolveLivenessStatus(session, observation);
  const nextSession = mergeSessionRecord(session, buildLivenessPatch(session, observation, nextStatus, now), {
    now,
    generateId: defaultGenerateId,
    mode: "update",
  });
  return nextSession;
}

function resolveLivenessStatus(session, observation = {}) {
  const processAlive = observation.processAlive === true;
  const hasActivity = observation.hasActivity === true;
  const hasNativeSession = Boolean(
    readNullableString(observation.nativeClaudeSessionId)
      || readNullableString(session.nativeClaudeSessionId)
  );

  if (processAlive) {
    if (session.status === MMSCHAT_STATUS.pending || session.status === MMSCHAT_STATUS.unknown) {
      return MMSCHAT_STATUS.running;
    }

    if (session.status === MMSCHAT_STATUS.running || session.status === MMSCHAT_STATUS.idle) {
      return hasActivity ? MMSCHAT_STATUS.running : MMSCHAT_STATUS.idle;
    }

    if (session.status === MMSCHAT_STATUS.needsResume) {
      return MMSCHAT_STATUS.running;
    }

    return session.status;
  }

  return hasNativeSession ? MMSCHAT_STATUS.needsResume : MMSCHAT_STATUS.dead;
}

function buildLivenessPatch(session, observation, nextStatus, now = () => Date.now()) {
  const patch = {
    status: nextStatus,
  };

  if (Object.prototype.hasOwnProperty.call(observation, "pid")) {
    patch.pid = observation.processAlive === false ? null : observation.pid;
  }

  if (Object.prototype.hasOwnProperty.call(observation, "tmuxPaneId")) {
    patch.tmuxPaneId = observation.tmuxPaneId;
  }

  if (Object.prototype.hasOwnProperty.call(observation, "tmuxSessionName")) {
    patch.tmuxSessionName = observation.tmuxSessionName;
  }

  if (Object.prototype.hasOwnProperty.call(observation, "nativeClaudeSessionId")) {
    patch.nativeClaudeSessionId = observation.nativeClaudeSessionId;
  }

  if (Object.prototype.hasOwnProperty.call(observation, "nativeClaudeSessionStatus")) {
    patch.nativeClaudeSessionStatus = observation.nativeClaudeSessionStatus;
  }

  if (Object.prototype.hasOwnProperty.call(observation, "lastPreviewText")) {
    patch.lastPreviewText = observation.lastPreviewText;
  }

  if (Object.prototype.hasOwnProperty.call(observation, "transcriptCacheState")) {
    patch.transcriptCacheState = observation.transcriptCacheState;
  } else if (observation.markTranscriptStale === true && session.transcriptCacheState === MMSCHAT_TRANSCRIPT_CACHE_STATE.fresh) {
    patch.transcriptCacheState = MMSCHAT_TRANSCRIPT_CACHE_STATE.stale;
  }

  if (observation.hasActivity === true && !Object.prototype.hasOwnProperty.call(observation, "lastActivityAt")) {
    patch.lastActivityAt = new Date(now()).toISOString();
  } else if (Object.prototype.hasOwnProperty.call(observation, "lastActivityAt")) {
    patch.lastActivityAt = observation.lastActivityAt;
  }

  if (observation.processAlive === false) {
    patch.pid = null;
  }

  return patch;
}

function listSessions(sessions, filters = {}) {
  const requestedStatuses = Array.isArray(filters.status) ? new Set(filters.status) : null;
  const includeHidden = filters.includeHidden === true;
  const cwd = readNullableString(filters.cwd);
  const limit = Number.isInteger(filters.limit) && filters.limit > 0 ? filters.limit : null;

  const visibleSessions = sessions
    .filter((session) => includeHidden || session.hidden !== true)
    .filter((session) => !requestedStatuses || requestedStatuses.size === 0 || requestedStatuses.has(session.status))
    .filter((session) => !cwd || session.cwd === cwd)
    .slice()
    .sort(compareSessionsByActivity);

  return limit ? visibleSessions.slice(0, limit) : visibleSessions;
}

function compareSessionsByActivity(left, right) {
  return toTimestamp(right.lastActivityAt) - toTimestamp(left.lastActivityAt);
}

function createSessionRecord(input, { now = () => Date.now(), generateId = defaultGenerateId } = {}) {
  const cwd = readRequiredString(input.cwd, "MMSChat register requires cwd.");
  const createdAt = toIsoString(input.createdAt, now);
  const lastActivityAt = toIsoString(input.lastActivityAt, () => Date.parse(createdAt));
  const mmschatId = normalizeMMSChatId(input.mmschatId, generateId);

  return {
    mmschatId,
    nativeClaudeSessionId: readNullableString(input.nativeClaudeSessionId),
    nativeClaudeSessionStatus: normalizeNativeSessionStatus(
      input.nativeClaudeSessionStatus,
      readNullableString(input.nativeClaudeSessionId),
      MMSCHAT_NATIVE_SESSION_STATUS.pending
    ),
    title: readNullableString(input.title),
    cwd,
    project: normalizeProject(input.project),
    agent: normalizeAgent(input.agent),
    provider: readNullableString(input.provider),
    model: readNullableString(input.model),
    launchProfileName: readNullableString(input.launchProfileName),
    launchProfileFingerprint: readNullableString(input.launchProfileFingerprint),
    authSecretRef: readNullableString(input.authSecretRef),
    tmuxPaneId: readNullableString(input.tmuxPaneId),
    tmuxSessionName: readNullableString(input.tmuxSessionName),
    pid: normalizePid(input.pid),
    status: normalizeStatus(input.status, MMSCHAT_STATUS.pending),
    createdAt,
    lastActivityAt,
    lastPreviewText: readNullableString(input.lastPreviewText),
    hidden: input.hidden === true,
    transcriptCacheState: normalizeTranscriptCacheState(input.transcriptCacheState),
    metadata: normalizeMetadata(input.metadata),
  };
}

function mergeSessionRecord(session, patch, { now = () => Date.now(), generateId = defaultGenerateId, mode = "update" } = {}) {
  const base = createSessionRecord(session, {
    now: () => Date.parse(session.createdAt || new Date(now()).toISOString()),
    generateId,
  });
  const next = { ...base };

  if (Object.prototype.hasOwnProperty.call(patch, "nativeClaudeSessionId")) {
    next.nativeClaudeSessionId = readNullableString(patch.nativeClaudeSessionId);
  }

  if (Object.prototype.hasOwnProperty.call(patch, "nativeClaudeSessionStatus")) {
    next.nativeClaudeSessionStatus = normalizeNativeSessionStatus(
      patch.nativeClaudeSessionStatus,
      next.nativeClaudeSessionId
    );
  } else if (!next.nativeClaudeSessionStatus) {
    next.nativeClaudeSessionStatus = normalizeNativeSessionStatus(null, next.nativeClaudeSessionId);
  }

  if (Object.prototype.hasOwnProperty.call(patch, "title")) {
    next.title = readNullableString(patch.title);
  }

  if (Object.prototype.hasOwnProperty.call(patch, "cwd")) {
    next.cwd = readRequiredString(patch.cwd, "MMSChat update requires cwd when cwd is provided.");
  }

  if (Object.prototype.hasOwnProperty.call(patch, "project")) {
    next.project = normalizeProject(patch.project);
  }

  if (Object.prototype.hasOwnProperty.call(patch, "agent")) {
    next.agent = normalizeAgent(patch.agent);
  }

  for (const field of [
    "provider",
    "model",
    "launchProfileName",
    "launchProfileFingerprint",
    "authSecretRef",
    "tmuxPaneId",
    "tmuxSessionName",
    "lastPreviewText",
  ]) {
    if (Object.prototype.hasOwnProperty.call(patch, field)) {
      next[field] = readNullableString(patch[field]);
    }
  }

  if (Object.prototype.hasOwnProperty.call(patch, "pid")) {
    next.pid = normalizePid(patch.pid);
  }

  if (Object.prototype.hasOwnProperty.call(patch, "status")) {
    next.status = transitionStatus(next.status, normalizeStatus(patch.status, next.status));
  }

  if (Object.prototype.hasOwnProperty.call(patch, "createdAt") && mode === "register") {
    next.createdAt = toIsoString(patch.createdAt, now);
  }

  const shouldTouchActivity = hasActivityPatch(patch);
  if (Object.prototype.hasOwnProperty.call(patch, "lastActivityAt")) {
    next.lastActivityAt = toIsoString(patch.lastActivityAt, now);
  } else if (shouldTouchActivity) {
    next.lastActivityAt = new Date(now()).toISOString();
  }

  if (Object.prototype.hasOwnProperty.call(patch, "hidden")) {
    next.hidden = patch.hidden === true;
  }

  if (Object.prototype.hasOwnProperty.call(patch, "transcriptCacheState")) {
    next.transcriptCacheState = normalizeTranscriptCacheState(patch.transcriptCacheState);
  }

  if (Object.prototype.hasOwnProperty.call(patch, "metadata")) {
    next.metadata = normalizeMetadata(patch.metadata);
  }

  next.nativeClaudeSessionStatus = normalizeNativeSessionStatus(
    next.nativeClaudeSessionStatus,
    next.nativeClaudeSessionId
  );

  return next;
}

function hasActivityPatch(patch) {
  return (Object.prototype.hasOwnProperty.call(patch, "lastPreviewText") && readNullableString(patch.lastPreviewText) !== null)
    || Object.prototype.hasOwnProperty.call(patch, "status")
    || patch.hasActivity === true;
}

function findExistingSessionIndex(sessions, input) {
  const byId = normalizeExistingId(input.mmschatId);
  if (byId) {
    return sessions.findIndex((session) => session.mmschatId === byId);
  }

  const nativeClaudeSessionId = readNullableString(input.nativeClaudeSessionId);
  if (nativeClaudeSessionId) {
    return sessions.findIndex((session) => session.nativeClaudeSessionId === nativeClaudeSessionId);
  }

  return -1;
}

function upsertSession(sessions, nextSession, existingIndex) {
  const nextSessions = sessions.slice();
  if (existingIndex >= 0) {
    nextSessions[existingIndex] = nextSession;
  } else {
    nextSessions.push(nextSession);
  }
  return nextSessions;
}

function mutateById(store, mmschatId, now, mutate) {
  const normalizedId = readRequiredString(mmschatId, "MMSChat request requires mmschatId.");
  const state = store.readState();
  const index = state.sessions.findIndex((session) => session.mmschatId === normalizedId);
  if (index < 0) {
    throw createRegistryError(MMSCHAT_ERROR_CODES.sessionNotFound, `Unknown MMSChat session: ${normalizedId}`);
  }

  const nextSession = mutate(state.sessions[index]);
  const nextSessions = state.sessions.slice();
  nextSessions[index] = nextSession;
  store.writeState({ ...state, sessions: nextSessions });
  return cloneJsonValue(nextSession);
}

function findSessionById(sessions, mmschatId) {
  const normalizedId = normalizeExistingId(mmschatId);
  if (!normalizedId) {
    return null;
  }

  return sessions.find((session) => session.mmschatId === normalizedId) || null;
}

function findSessionByNativeClaudeSessionId(sessions, nativeClaudeSessionId) {
  const normalizedId = readNullableString(nativeClaudeSessionId);
  if (!normalizedId) {
    return null;
  }

  return sessions.find((session) => session.nativeClaudeSessionId === normalizedId) || null;
}

function normalizeUpdateInput(sessionOrId, patch) {
  if (isPlainObject(sessionOrId)) {
    const record = sessionOrId;
    return {
      mmschatId: readRequiredString(record.mmschatId, "MMSChat request requires mmschatId."),
      patch: record,
    };
  }

  return {
    mmschatId: readRequiredString(sessionOrId, "MMSChat request requires mmschatId."),
    patch: isPlainObject(patch) ? patch : {},
  };
}

function assertNoPersistedSecrets(value, trail = []) {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => assertNoPersistedSecrets(entry, trail.concat(String(index))));
    return;
  }

  if (!isPlainObject(value)) {
    return;
  }

  for (const [key, nestedValue] of Object.entries(value)) {
    const normalizedKey = normalizeSecretKey(key);
    if (isForbiddenPersistedKey(normalizedKey)) {
      const joinedPath = trail.concat(key).join(".");
      throw createRegistryError(MMSCHAT_ERROR_CODES.secretRejected, `Refusing to persist secret-like field: ${joinedPath}`);
    }
    assertNoPersistedSecrets(nestedValue, trail.concat(key));
  }
}

function isForbiddenPersistedKey(normalizedKey) {
  if (!normalizedKey || normalizedKey === "authsecretref") {
    return false;
  }

  return normalizedKey === "apikey"
    || normalizedKey === "authtoken"
    || normalizedKey === "token"
    || normalizedKey === "sessionid"
    || normalizedKey === "relaysessionid"
    || normalizedKey === "pairingsecret"
    || normalizedKey === "transcriptsecret"
    || normalizedKey === "providercredential"
    || normalizedKey === "providercredentials"
    || normalizedKey === "credentialmaterial"
    || normalizedKey === "accesstoken"
    || normalizedKey === "refreshtoken";
}

function normalizeSecretKey(value) {
  return String(value || "").replace(/[^a-z0-9]/gi, "").toLowerCase();
}

function normalizeMMSChatId(value, generateId) {
  const provided = normalizeExistingId(value);
  if (provided) {
    return provided;
  }

  return generateId();
}

function normalizeExistingId(value) {
  const stringValue = readNullableString(value);
  if (!stringValue) {
    return null;
  }

  if (!/^mmschat_[A-Za-z0-9_-]+$/.test(stringValue)) {
    throw createRegistryError(MMSCHAT_ERROR_CODES.invalidParams, `Invalid MMSChat id: ${stringValue}`);
  }

  return stringValue;
}

function normalizeStatus(value, fallback) {
  const candidate = readNullableString(value);
  if (!candidate) {
    return fallback;
  }

  if (!Object.values(MMSCHAT_STATUS).includes(candidate)) {
    throw createRegistryError(MMSCHAT_ERROR_CODES.invalidParams, `Invalid MMSChat status: ${candidate}`);
  }

  return candidate;
}

function transitionStatus(fromStatus, toStatus) {
  if (!toStatus || toStatus === fromStatus) {
    return fromStatus;
  }

  if (!canTransitionMMSChatStatus(fromStatus, toStatus)) {
    throw createRegistryError(MMSCHAT_ERROR_CODES.invalidParams, `Invalid MMSChat status transition: ${fromStatus} -> ${toStatus}`);
  }

  return toStatus;
}

function normalizeNativeSessionStatus(value, nativeClaudeSessionId, fallbackStatus = MMSCHAT_NATIVE_SESSION_STATUS.unavailable) {
  const candidate = readNullableString(value);
  if (!candidate) {
    return nativeClaudeSessionId ? MMSCHAT_NATIVE_SESSION_STATUS.pending : fallbackStatus;
  }

  if (!Object.values(MMSCHAT_NATIVE_SESSION_STATUS).includes(candidate)) {
    throw createRegistryError(MMSCHAT_ERROR_CODES.invalidParams, `Invalid native session status: ${candidate}`);
  }

  return candidate;
}

function normalizeTranscriptCacheState(value) {
  const candidate = readNullableString(value);
  if (!candidate) {
    return MMSCHAT_TRANSCRIPT_CACHE_STATE.empty;
  }

  if (!Object.values(MMSCHAT_TRANSCRIPT_CACHE_STATE).includes(candidate)) {
    throw createRegistryError(MMSCHAT_ERROR_CODES.invalidParams, `Invalid transcript cache state: ${candidate}`);
  }

  return candidate;
}

function normalizeAgent(value) {
  const candidate = readNullableString(value);
  if (!candidate) {
    return "claude";
  }

  if (candidate !== "claude" && candidate !== "codex") {
    throw createRegistryError(MMSCHAT_ERROR_CODES.invalidParams, `Unsupported MMSChat agent: ${candidate}`);
  }

  return candidate;
}

function normalizePid(value) {
  return Number.isInteger(value) && value > 0 ? value : null;
}

function normalizeProject(value) {
  return readNullableString(value);
}

function normalizeMetadata(value) {
  if (value == null) {
    return null;
  }

  if (!isPlainObject(value)) {
    throw createRegistryError(MMSCHAT_ERROR_CODES.invalidParams, "MMSChat metadata must be an object.");
  }

  return cloneJsonValue(value);
}

function toIsoString(value, fallback) {
  if (typeof value === "string") {
    const timestamp = Date.parse(value);
    if (!Number.isNaN(timestamp)) {
      return new Date(timestamp).toISOString();
    }
  }

  const fallbackValue = typeof fallback === "function" ? fallback() : fallback;
  return new Date(fallbackValue).toISOString();
}

function toTimestamp(value) {
  const timestamp = Date.parse(value);
  return Number.isNaN(timestamp) ? 0 : timestamp;
}

function readNullableString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function readRequiredString(value, message) {
  const stringValue = readNullableString(value);
  if (!stringValue) {
    throw createRegistryError(MMSCHAT_ERROR_CODES.invalidParams, message);
  }

  return stringValue;
}

function cloneOrNull(value) {
  return value ? cloneJsonValue(value) : null;
}

function defaultGenerateId() {
  return `mmschat_${crypto.randomBytes(9).toString("base64url")}`;
}

function createRegistryError(errorCode, message) {
  const error = new Error(message);
  error.errorCode = errorCode;
  return error;
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function cloneJsonValue(value) {
  return JSON.parse(JSON.stringify(value));
}

module.exports = {
  SESSION_FIELDS,
  applyLivenessTransition,
  assertNoPersistedSecrets,
  createMMSChatRegistry,
  createRegistryError,
  listSessions,
  resolveLivenessStatus,
};
