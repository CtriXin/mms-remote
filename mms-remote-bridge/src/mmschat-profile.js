// FILE: mmschat-profile.js
// Purpose: Normalizes non-secret MMSChat provider/model launch profile metadata.
// Layer: Service helper
// Exports: MMSChat profile normalization, comparison, and resume candidate helpers.
// Depends on: ./agent-launcher

const { resolveLaunchProfile } = require("./agent-launcher");

const LIVE_RESUME_COMPATIBILITY = "unverified_live_matrix_pending";
const MMSCHAT_PROFILE_FIELDS = Object.freeze([
  "provider",
  "model",
  "launchProfileName",
  "launchProfileFingerprint",
  "authSecretRef",
  "credentialPresent",
]);
const MMSCHAT_PROFILE_ERROR_CODES = Object.freeze({
  secretRejected: "mmschat_profile_secret_rejected",
});
const RAW_SECRET_FIELD_NAMES = new Set([
  "accesstoken",
  "apikey",
  "authtoken",
  "credential",
  "credentialmaterial",
  "credentials",
  "password",
  "pairingsecret",
  "providercredential",
  "providercredentials",
  "refreshtoken",
  "relaysessionid",
  "secret",
  "sessionid",
  "token",
]);
const RAW_SECRET_VALUE_PATTERNS = Object.freeze([
  /^sk-[A-Za-z0-9_-]{8,}/,
  /^xox[baprs]-[A-Za-z0-9-]{8,}/,
  /^gh[pousr]_[A-Za-z0-9_]{20,}/,
  /^AKIA[A-Z0-9]{16}$/,
  /^[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$/,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/,
]);

function resolveMMSChatProfile({ agent = "claude", config = {}, model = "", preset = "", provider = "" } = {}) {
  assertNoSecretMaterial({ config, model, preset, provider });
  return normalizeMMSChatProfile(resolveLaunchProfile({
    agent,
    config,
    model,
    preset,
    provider,
  }));
}

function normalizeMMSChatProfile(profile = {}) {
  assertNoSecretMaterial(profile);
  return {
    provider: readNullableString(profile.provider),
    model: readNullableString(profile.model),
    launchProfileName: readNullableString(profile.launchProfileName),
    launchProfileFingerprint: readNullableString(profile.launchProfileFingerprint),
    authSecretRef: normalizeAuthSecretRef(profile.authSecretRef),
    credentialPresent: profile.credentialPresent === true,
  };
}

function summarizeMMSChatProfile(profile = null) {
  if (!profile) {
    return null;
  }

  const normalized = normalizeMMSChatProfile(profile);
  return {
    provider: normalized.provider,
    model: normalized.model,
    launchProfileName: normalized.launchProfileName,
    launchProfileFingerprint: normalized.launchProfileFingerprint,
    authSecretRefPresent: Boolean(normalized.authSecretRef),
    credentialPresent: normalized.credentialPresent,
  };
}

function compareMMSChatProfiles({ lastKnown = null, current = null } = {}) {
  const normalizedLastKnown = lastKnown ? normalizeMMSChatProfile(lastKnown) : null;
  const normalizedCurrent = current ? normalizeMMSChatProfile(current) : null;

  if (!normalizedLastKnown && !normalizedCurrent) {
    return createComparison("missing", false, [], normalizedLastKnown, normalizedCurrent);
  }
  if (!normalizedLastKnown) {
    return createComparison("last_known_missing", false, MMSCHAT_PROFILE_FIELDS, normalizedLastKnown, normalizedCurrent);
  }
  if (!normalizedCurrent) {
    return createComparison("current_missing", false, MMSCHAT_PROFILE_FIELDS, normalizedLastKnown, normalizedCurrent);
  }

  const changedFields = MMSCHAT_PROFILE_FIELDS.filter((field) => normalizedLastKnown[field] !== normalizedCurrent[field]);
  return createComparison(
    changedFields.length === 0 ? "match" : "changed",
    changedFields.length === 0,
    changedFields,
    normalizedLastKnown,
    normalizedCurrent
  );
}

function buildResumeProfileCandidates({ lastKnown = null, current = null } = {}) {
  const candidates = [];
  const seen = new Set();
  appendResumeCandidate(candidates, seen, "lastKnown", lastKnown);
  appendResumeCandidate(candidates, seen, "current", current);
  return candidates;
}

function appendResumeCandidate(candidates, seen, source, profile) {
  if (!profile) {
    return;
  }

  const normalized = normalizeMMSChatProfile(profile);
  if (!hasProfileSignal(normalized)) {
    return;
  }

  const dedupeKey = JSON.stringify(normalized);
  if (seen.has(dedupeKey)) {
    return;
  }

  seen.add(dedupeKey);
  candidates.push({
    source,
    ...normalized,
    liveResumeCompatibility: LIVE_RESUME_COMPATIBILITY,
  });
}

function createComparison(status, matches, changedFields, lastKnown, current) {
  return {
    status,
    matches,
    changedFields,
    authSecretRefChanged: changedFields.includes("authSecretRef"),
    lastKnown: summarizeNormalizedProfile(lastKnown),
    current: summarizeNormalizedProfile(current),
  };
}

function summarizeNormalizedProfile(profile) {
  if (!profile) {
    return null;
  }

  return {
    provider: profile.provider,
    model: profile.model,
    launchProfileName: profile.launchProfileName,
    launchProfileFingerprint: profile.launchProfileFingerprint,
    authSecretRefPresent: Boolean(profile.authSecretRef),
    credentialPresent: profile.credentialPresent,
  };
}

function hasProfileSignal(profile) {
  return Boolean(
    profile.provider
      || profile.model
      || profile.launchProfileName
      || profile.launchProfileFingerprint
      || profile.authSecretRef
      || profile.credentialPresent
  );
}

function assertNoSecretMaterial(value, trail = []) {
  if (Array.isArray(value)) {
    value.forEach((entry, index) => assertNoSecretMaterial(entry, trail.concat(String(index))));
    return;
  }

  if (!isPlainObject(value)) {
    assertSafeStringValue(value, trail);
    return;
  }

  for (const [key, nestedValue] of Object.entries(value)) {
    const normalizedKey = normalizeSecretKey(key);
    if (normalizedKey === "authsecretref") {
      normalizeAuthSecretRef(nestedValue, trail.concat(key));
      continue;
    }
    if (RAW_SECRET_FIELD_NAMES.has(normalizedKey)) {
      throw createProfileError(`Refusing raw secret-like field: ${trail.concat(key).join(".")}`);
    }
    assertNoSecretMaterial(nestedValue, trail.concat(key));
  }
}

function assertSafeStringValue(value, trail) {
  if (typeof value !== "string") {
    return;
  }

  if (looksLikeRawSecret(value)) {
    throw createProfileError(`Refusing raw secret-like value at ${trail.join(".") || "value"}`);
  }
}

function normalizeAuthSecretRef(value, trail = ["authSecretRef"]) {
  const normalized = readNullableString(value);
  if (!normalized) {
    return null;
  }
  if (looksLikeRawSecret(normalized)) {
    throw createProfileError(`Refusing raw secret-like authSecretRef at ${trail.join(".")}`);
  }
  return normalized;
}

function looksLikeRawSecret(value) {
  const normalized = String(value || "").trim();
  if (!normalized) {
    return false;
  }
  return RAW_SECRET_VALUE_PATTERNS.some((pattern) => pattern.test(normalized));
}

function createProfileError(message) {
  const error = new Error(message);
  error.errorCode = MMSCHAT_PROFILE_ERROR_CODES.secretRejected;
  return error;
}

function normalizeSecretKey(value) {
  return String(value || "").replace(/[^a-z0-9]/gi, "").toLowerCase();
}

function readNullableString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

module.exports = {
  LIVE_RESUME_COMPATIBILITY,
  MMSCHAT_PROFILE_ERROR_CODES,
  MMSCHAT_PROFILE_FIELDS,
  assertNoSecretMaterial,
  buildResumeProfileCandidates,
  compareMMSChatProfiles,
  normalizeMMSChatProfile,
  resolveMMSChatProfile,
  summarizeMMSChatProfile,
};
