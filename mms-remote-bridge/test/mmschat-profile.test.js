// FILE: mmschat-profile.test.js
// Purpose: Verifies MMSChat provider/model profile helpers stay offline and secret-safe.
// Layer: Unit test
// Exports: node:test suite
// Depends on: node:test, node:assert/strict, ../src/mmschat-profile

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  LIVE_RESUME_COMPATIBILITY,
  MMSCHAT_PROFILE_ERROR_CODES,
  buildResumeProfileCandidates,
  compareMMSChatProfiles,
  normalizeMMSChatProfile,
  resolveMMSChatProfile,
  summarizeMMSChatProfile,
} = require("../src/mmschat-profile");

test("mmschat-profile resolves stable non-secret profile metadata from sanitized config", () => {
  const profile = resolveMMSChatProfile({
    agent: "claude",
    config: createSanitizedConfigFixture(),
    preset: "fast",
  });
  const repeated = resolveMMSChatProfile({
    agent: "claude",
    config: createSanitizedConfigFixture(),
    preset: "fast",
  });

  assert.deepEqual(Object.keys(profile), [
    "provider",
    "model",
    "launchProfileName",
    "launchProfileFingerprint",
    "authSecretRef",
    "credentialPresent",
  ]);
  assert.equal(profile.provider, "kimi");
  assert.equal(profile.model, "kimi-k2");
  assert.equal(profile.launchProfileName, "fast");
  assert.match(profile.launchProfileFingerprint, /^sha256:[a-f0-9]{64}$/);
  assert.equal(profile.launchProfileFingerprint, repeated.launchProfileFingerprint);
  assert.equal(profile.authSecretRef, "keychain:mms/kimi-fast");
  assert.equal(profile.credentialPresent, true);
  assert.doesNotMatch(JSON.stringify(profile), /sk-live-secret|raw-token|preset/);
});

test("mmschat-profile rejects raw credential keys and raw-looking secret refs", () => {
  assert.throws(() => {
    normalizeMMSChatProfile({
      provider: "kimi",
      apiKey: "sk-live-secret",
    });
  }, hasSecretRejectedCode);

  assert.throws(() => {
    resolveMMSChatProfile({
      config: {
        providers: [{ id: "kimi", defaultModel: "kimi-k2", api_key: "sk-live-secret" }],
        presets: {},
      },
      provider: "kimi",
    });
  }, hasSecretRejectedCode);

  assert.throws(() => {
    normalizeMMSChatProfile({
      authSecretRef: "sk-live-secret-material",
    });
  }, hasSecretRejectedCode);
});

test("mmschat-profile comparison redacts auth refs while reporting changed profile fields", () => {
  const comparison = compareMMSChatProfiles({
    lastKnown: {
      provider: "kimi",
      model: "kimi-k2",
      launchProfileName: "fast",
      launchProfileFingerprint: "sha256:last",
      authSecretRef: "keychain:mms/kimi-fast",
      credentialPresent: true,
    },
    current: {
      provider: "kimi",
      model: "kimi-k2-2026",
      launchProfileName: "fast",
      launchProfileFingerprint: "sha256:current",
      authSecretRef: "keychain:mms/kimi-current",
      credentialPresent: true,
    },
  });
  const serialized = JSON.stringify(comparison);

  assert.equal(comparison.status, "changed");
  assert.equal(comparison.matches, false);
  assert.deepEqual(comparison.changedFields, ["model", "launchProfileFingerprint", "authSecretRef"]);
  assert.equal(comparison.authSecretRefChanged, true);
  assert.equal(comparison.lastKnown.authSecretRefPresent, true);
  assert.equal(comparison.current.authSecretRefPresent, true);
  assert.doesNotMatch(serialized, /keychain:mms\/kimi/);
});

test("mmschat-profile generates resume candidates from saved non-secret refs only", () => {
  const lastKnown = resolveMMSChatProfile({
    agent: "claude",
    config: createSanitizedConfigFixture(),
    preset: "fast",
  });
  const candidates = buildResumeProfileCandidates({
    lastKnown,
    current: { ...lastKnown },
  });
  const candidate = candidates[0];
  const serialized = JSON.stringify(candidates);

  assert.equal(candidates.length, 1);
  assert.equal(candidate.source, "lastKnown");
  assert.equal(candidate.provider, "kimi");
  assert.equal(candidate.model, "kimi-k2");
  assert.equal(candidate.authSecretRef, "keychain:mms/kimi-fast");
  assert.equal(candidate.credentialPresent, true);
  assert.equal(candidate.liveResumeCompatibility, LIVE_RESUME_COMPATIBILITY);
  assert.equal(Object.prototype.hasOwnProperty.call(candidate, "env"), false);
  assert.doesNotMatch(serialized, /sk-live-secret|raw-token/);
});

test("mmschat-profile summaries expose presence flags instead of authSecretRef values", () => {
  const summary = summarizeMMSChatProfile({
    provider: "mimo",
    model: "mimo-v2.5",
    launchProfileName: "mimo-local",
    launchProfileFingerprint: "sha256:mimo",
    authSecretRef: "profile:mimo/local",
    credentialPresent: true,
  });

  assert.deepEqual(summary, {
    provider: "mimo",
    model: "mimo-v2.5",
    launchProfileName: "mimo-local",
    launchProfileFingerprint: "sha256:mimo",
    authSecretRefPresent: true,
    credentialPresent: true,
  });
  assert.equal(Object.prototype.hasOwnProperty.call(summary, "authSecretRef"), false);
});

function createSanitizedConfigFixture() {
  return {
    found: true,
    providers: [
      {
        id: "kimi",
        name: "Kimi",
        cli: "claude",
        defaultModel: "kimi-k2",
        authSecretRef: "keychain:mms/kimi",
        credentialPresent: true,
      },
    ],
    presets: {
      fast: {
        provider: "kimi",
        model: "kimi-k2",
        authSecretRef: "keychain:mms/kimi-fast",
        credentialPresent: true,
      },
    },
    overlays: {},
    metadata: { title: "fixture" },
  };
}

function hasSecretRejectedCode(error) {
  return error?.errorCode === MMSCHAT_PROFILE_ERROR_CODES.secretRejected;
}
