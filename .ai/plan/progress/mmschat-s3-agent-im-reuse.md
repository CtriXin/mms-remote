# MMSChat S3 agent-im Reuse Assessment

- task: `s184-0-mmschat-phase0-s0-s3`
- trace_id: `trc-20260516T082907Z-f43b858883`
- commit: `1cc3ceab49a2b2e2c32802968073d25a26cb347e`
- current_head: `dae9397f91fd73b7e4255e051169601a6451fe05` (pack commit is ancestor; user instructed executor to continue after drift)
- refs read-only: `/Users/xin/auto-skills/CtriXin-repo/agent-im/src/session-registry.ts`, `/Users/xin/auto-skills/CtriXin-repo/agent-im/src/store.ts`

## Conclusion

Reuse agent-im concepts, not code wholesale. MMSChat should copy the lifecycle/store patterns, but must replace auth storage, logging, data directory, and Discord/hub-specific concepts to preserve mms-remote local-first and auth-secret-ref constraints.

## Reuse Concepts

| Concept | Reuse decision | MMSChat adaptation |
|---|---|---|
| Session lifecycle states | Reuse | `pending`, `running/active`, `idle`, `dead`, `needs-resume`, `unknown`; map final names in P0 schema. |
| `lastActivityAt`-sorted visible list | Reuse | Drives MMSChat list ordering and stale session cleanup. |
| Register/update/list API shape | Reuse | Build bridge registry around `register`, `update`, `list`, `hide`, `clear-cache`, `getByNativeClaudeSessionId`. |
| Periodic cleanup and PID liveness check | Reuse with caution | Useful for status transitions; do not mark Claude native session deleted when process dies. |
| EventEmitter-style registry events | Reuse | Bridge can notify local WebSocket/RPC subscribers when session status or preview changes. |
| Atomic write via temp file + rename | Reuse | Good baseline for local JSON store durability. |
| Read fallback on corrupt/missing JSON | Reuse | Add backup/quarantine so corrupt store does not crash bridge or erase native Claude state. |
| Sync-from-disk before reads/writes | Reuse | Helps multiple local bridge/helper processes avoid stale reads. |
| Provider/model/baseUrl metadata | Reuse concept | Store provider/model/profile fingerprint only; never store live secrets. |

## Do Not Copy Directly

| agent-im detail | Why not copy | Replacement |
|---|---|---|
| `authToken?: string` in `CLISession` | Violates MMSChat `authSecretRef` rule and open-source/self-hosted safety. | Store `authSecretRef`, `launchProfileName`, `launchProfileFingerprint`; credentials stay in existing secret store/profile. |
| Logs with `sessionId.slice(0, 8)` | Project rule says live relay/session-like bearer identifiers should be redacted or hashed. Claude session IDs should also be treated conservatively. | Log stable hashes only, or avoid IDs in normal logs. |
| Discord/hub fields (`hubMessageId`, permission Discord IDs) | Product/domain mismatch. | Use local bridge RPC state and iOS UI state only. |
| SDK sessions are always dead after daemon restart | MMSChat needs native Claude session persistence and resume semantics. | Dead process can become `needs-resume`, not deleted. |
| `DATA_DIR` from agent-im config | Wrong ownership/lifecycle. | Use mms-remote bridge-owned local data directory; do not reset on pairing cleanup. |
| `authToken`/`baseUrl` as resume source | Leaks or over-couples provider credentials. | Profile fingerprint + `authSecretRef`; resume command constructed from trusted local profile. |
| Synchronous `git rev-parse` on every registration | Can block or fail on non-git cwd. | Keep optional bounded project/branch detection with timeout and fallback. |

## MMSChat Store Shape Guidance

P1 can use an agent-im-inspired store, but with MMSChat-specific records:

```text
MMSChatSession
  mmschatId
  nativeClaudeSessionId
  cwd/project
  agent/provider/model
  launchProfileName/launchProfileFingerprint/authSecretRef
  tmuxSessionName/tmuxPaneId/pid
  status/createdAt/lastActivityAt/lastPreviewText
  hidden
```

Store boundaries:

- Local bridge disk only; no hosted-service assumption or hardcoded production domain.
- Do not store API keys, auth tokens, relay `sessionId`, pairing secret, or transcript secrets.
- Keep Claude native JSONL as source of truth; MMSChat store is an index/cache.
- Pairing reset must not delete Claude native sessions or MMSChat registry by accident.
- iOS should receive data through existing local Bridge auth; if cached on device, keep only minimal display/cache data and follow existing local/E2EE behavior.

## P0/P1 Implication

- P0 should freeze IDs and status transitions with `nativeClaudeSessionId` nullable/pending.
- P1 should implement an atomic JSON store and registry API from scratch in mms-remote style.
- P1 tests should cover corrupt JSON fallback, atomic persistence, hide vs kill vs destroy semantics, stale PID transition to `needs-resume`, and secret non-persistence.
