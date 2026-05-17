# P184 MMSChat Project Fresh Session Handover

- timestamp: 2026-05-16T09:24:26Z
- timestamp_bjt: 2026-05-16 17:24:26 BJT
- owner: codex-planner-handler
- cli: codex
- model: gpt-5.5
- task_id: p184-mmschat-project-handover
- moebius_run_id: p184-mmschat-20260516
- moebius_trace_id: trc-20260516T082907Z-f43b858883
- status: phase0_executor_pack_ready

## One-Line Truth

This repo has an active Mobius-governed MMSChat project, but current main process must stay safe. Start with executor pack `s184-0-mmschat-phase0-s0-s3` only; no product code until Phase0 result is accepted.

## Existing Project Progress To Preserve

Current top-level project work before MMSChat:

- Terminal/SwiftTerm stabilization active.
- Current stable checkpoint in `.ai/plan/current.md`: `1.7.24 build 60` installed on `song的iPhone`, launch blocked by locked phone, user smoke pending.
- Stable renderer stays default/trusted.
- SwiftTerm live renderer remains experimental.
- Do not run Xcode tests unless user explicitly asks.
- Do not install to `iPhone 15 ProX雨`.

## MMSChat Direction

- Source of truth: Claude native session.
- MMSChat: session index + status + transcript cache + Chat-like UI.
- Terminal: shell/PTY control panel; keep boundary clear.
- MVP: read-only list/detail first; `send` behind feature flag and busy guard later.
- UI entry: Terminal Tab segmented control `Terminal | Sessions`.
- Default execution: single branch sequential; use worktree only if main process remains active/dirty or user approves acceleration.

## Stable Baseline

- branch: `main`
- stable_commit: `1cc3ceab49a2b2e2c32802968073d25a26cb347e`
- commit subject: `docs: update terminal planning and guardrails`
- Mobius handler repo: `/Users/xin/auto-skills/CtriXin-repo/moebius`
- Mobius trace: `trc-20260516T082907Z-f43b858883`

## Current Executor Pack

- pack: `.ai/exec/packs/s184-0-mmschat-phase0-s0-s3.json`
- human pack: `.ai/exec/packs/s184-0-mmschat-phase0-s0-s3.md`
- command: `/executor s184-0-mmschat-phase0-s0-s3 1cc3ceab49a2b2e2c32802968073d25a26cb347e executor=<model-id>`

Allowed Phase0 writes:

- `.ai/plan/progress/mmschat-s0-transcript-source.md`
- `.ai/plan/progress/mmschat-s3-agent-im-reuse.md`
- `.ai/plan/p184-mmschat-phase0-result.json`
- `.ai/plan/p184-mmschat-phase0-result.md`
- `.ai/exec/results/<EXECUTOR_ID>/s184-0-mmschat-phase0-s0-s3-result-YYYYMMDD.md`

Forbidden in Phase0:

- product code in `CodexMobile/`, `mms-remote-bridge/src`, `mms-remote-bridge/test`, `relay/`
- new paid/live Claude/model sessions
- provider resume matrix S1
- live `tmux send-keys` S2
- deploy, push, global config, destructive cleanup
- full private transcript dumps

## Phase0 Output Must Answer

- transcript source priority: native file / JSON stream / tmux capture / raw-only fallback
- safest `nativeClaudeSessionId` strategy
- `agent-im` registry/store reuse ideas
- what not to copy due local-first/E2EE/auth-secret-ref constraints
- whether P0 can start or HumanGate is needed

## Future Implementation Order After Phase0

- P0: protocol + model spec; likely needs separate worktree if main stays busy.
- P1: bridge registry/store.
- P2: Claude launcher integration.
- P3: transcript observation based on S0 result.
- P4: iOS list/detail UI, mock-first.
- P5: actions, send behind feature flag.
- P6: provider/model profile and resume behavior after S1 approval.
- P7: final integration/segmented control/localization/project files/version bump.

## Fresh Session Read Order In This Repo

1. `AGENTS.md`
2. `.ai/plan/current.md`
3. `.ai/plan/handoff.md`
4. `.ai/plan/p184-mmschat-fresh-session-handover.md`
5. `.ai/plan/mmschat-execution-plan-v2.md`
6. `.ai/exec/packs/s184-0-mmschat-phase0-s0-s3.json`
7. `/Users/xin/auto-skills/CtriXin-repo/moebius/.ai/plan/p184-mmschat-fresh-session-handover.md`

## Executor Start Prompt

```text
cd /Users/xin/auto-skills/CtriXin-repo/mms-remote
/executor s184-0-mmschat-phase0-s0-s3 1cc3ceab49a2b2e2c32802968073d25a26cb347e executor=<model-id>
```

## Host Intake

When done, tell Mobius supervisor to read:

- `.ai/plan/p184-mmschat-phase0-result.json`
- `.ai/plan/p184-mmschat-phase0-result.md`
- `.ai/plan/progress/mmschat-s0-transcript-source.md`
- `.ai/plan/progress/mmschat-s3-agent-im-reuse.md`
- `.ai/exec/results/*/s184-0-mmschat-phase0-s0-s3-result-*.md`
