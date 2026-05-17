// FILE: mmschat-demo-fixtures.js
// Purpose: Seeds explicit local-only MMSChat demo registry and cache data without native Claude access.
// Layer: Test/dev fixture helper
// Exports: Local MMSChat demo fixture seeder
// Depends on: ./mmschat-protocol, ./mmschat-transcript

const {
  MMSCHAT_NATIVE_SESSION_STATUS,
  MMSCHAT_STATUS,
  MMSCHAT_TRANSCRIPT_CACHE_STATE,
} = require("./mmschat-protocol");
const { writeMMSChatTranscriptCache } = require("./mmschat-transcript");

const DEMO_SOURCE = "mmschat-local-demo-fixture";
const DEFAULT_DEMO_CWD = "/tmp/mmschat-demo";

function seedMMSChatDemoFixtures(options = {}, params = {}) {
  const registry = options.registry;
  if (!registry || typeof registry.register !== "function") {
    throw new Error("MMSChat demo fixtures require a registry.");
  }

  const writeTranscriptCache = options.writeTranscriptCache || writeMMSChatTranscriptCache;
  const transcriptOptions = options.transcriptOptions || {};
  const now = options.now || (() => Date.now());
  const cwd = readOptionalString(params.cwd) || DEFAULT_DEMO_CWD;
  const seededAt = new Date(now()).toISOString();

  const sessions = buildDemoSessions(cwd, seededAt).map((fixture) => {
    const session = registry.register(fixture.session);
    writeTranscriptCache(fixture.transcript, {
      ...transcriptOptions,
      mmschatId: session.mmschatId,
    });
    return session;
  });

  return {
    demo: true,
    seeded: true,
    source: DEMO_SOURCE,
    sessions,
  };
}

function buildDemoSessions(cwd, seededAt) {
  const secondCwd = `${cwd.replace(/[\\/]+$/, "")}-review`;
  return [
    {
      session: {
        mmschatId: "mmschat_demo_local_project",
        nativeClaudeSessionId: "demo-native-local-1",
        nativeClaudeSessionStatus: MMSCHAT_NATIVE_SESSION_STATUS.confirmed,
        title: "Local demo: project briefing",
        cwd,
        project: "mmschat-demo",
        agent: "claude",
        provider: "local-demo",
        model: "demo-safe-model",
        launchProfileName: "demo-fixture",
        launchProfileFingerprint: "sha256:mmschat-demo-fixture",
        status: MMSCHAT_STATUS.idle,
        createdAt: "2026-05-16T08:29:07.000Z",
        lastActivityAt: seededAt,
        lastPreviewText: "Demo transcript is cached locally; no native Claude files were read.",
        transcriptCacheState: MMSCHAT_TRANSCRIPT_CACHE_STATE.fresh,
        metadata: {
          demo: "true",
          source: DEMO_SOURCE,
        },
      },
      transcript: {
        messages: [
          demoMessage("demo-native-local-1", "user", "Summarize the local MMSChat state."),
          demoMessage("demo-native-local-1", "assistant", "Two local demo sessions are available with cached transcript snapshots and safe model metadata."),
        ],
        rawPreviewText: null,
      },
    },
    {
      session: {
        mmschatId: "mmschat_demo_cache_review",
        nativeClaudeSessionId: "demo-native-local-2",
        nativeClaudeSessionStatus: MMSCHAT_NATIVE_SESSION_STATUS.confirmed,
        title: "Local demo: cache review",
        cwd: secondCwd,
        project: "mmschat-demo-review",
        agent: "claude",
        provider: "local-demo",
        model: "demo-safe-model",
        launchProfileName: "demo-fixture",
        launchProfileFingerprint: "sha256:mmschat-demo-fixture",
        status: MMSCHAT_STATUS.needsResume,
        createdAt: "2026-05-16T08:35:07.000Z",
        lastActivityAt: seededAt,
        lastPreviewText: "Cache clear and hide actions can be tested against this offline session.",
        transcriptCacheState: MMSCHAT_TRANSCRIPT_CACHE_STATE.fresh,
        metadata: {
          demo: "true",
          source: DEMO_SOURCE,
        },
      },
      transcript: {
        messages: [
          demoMessage("demo-native-local-2", "user", "Can I clear this cache safely?"),
          demoMessage("demo-native-local-2", "assistant", "Yes. The cache is an MMSChat snapshot under the bridge state directory, not native Claude history."),
        ],
        rawPreviewText: null,
      },
    },
  ];
}

function demoMessage(sessionId, role, text) {
  return {
    sessionId,
    role,
    timestamp: "2026-05-16T08:29:07.000Z",
    type: "message",
    content: [{ kind: "text", text }],
  };
}

function readOptionalString(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

module.exports = {
  DEFAULT_DEMO_CWD,
  DEMO_SOURCE,
  seedMMSChatDemoFixtures,
};
