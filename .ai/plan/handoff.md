# Handoff Log

## 2026-05-18T06:58:28-04:00 | agent=codex | cli=codex | model=gpt-5 | task=main-final-docs-cleanup-20260518
- TL;DR: Cleaned up the final main handoff so Terminal/localization merge state, upstream Remodex watchlist, and local-cache policy are all durable and current.
- Next action: Continue from `main`; app code baseline is `39d623d` / iOS `1.7.111 (149)`, docs baseline before this commit is `2874a88`.
- Scope / boundary: Docs and `.gitignore` only; no iOS or Bridge code changed, no version/build bump, no tests, no worktree cleanup.
- Changed files: `.gitignore`, `.ai/plan/current.md`, `.ai/plan/fresh-session-continue-prompt.md`, `.ai/plan/next-agent-prompt.md`, `.ai/plan/handoff.md`, `.ai/plan/v2-roadmap.md`, `.ai/plan/packet.json`, `.ai/plan/packet.toon`, `.ai/plan/progress/upstream-remodex-watchlist-20260518.md`, `.ai/plan/progress/upstream-remodex-watchlist-20260518.toon`, `.ai/plan/current-owner.json`, `.ai/plan/current-audit.jsonl`.
- Validation: planned `git diff --check`; local cache/tool dirs should remain uncommitted/ignored: `.codegraph/`, `.omc/`, `mms-remote-bridge/.omc/`, `tmp/`.
- Open risks: Terminal TUI replay/resize 乱码 remains a future专项; this docs pass does not change runtime behavior.

## 2026-05-18T06:54:00-04:00 | agent=codex | cli=codex | model=gpt-5 | task=upstream-remodex-watchlist-20260518
- TL;DR: Recorded all upstream Remodex/license/contribution conclusions into durable handoff docs and packet files.
- Next action: Continue MMS Remote development from `main`; use upstream only as reference unless user explicitly reopens contribution/PR work.
- Scope / boundary: Docs/metadata only; no iOS or Bridge code changed, no version/build bump, no tests, no worktree cleanup.
- Changed files: `.ai/plan/current.md`, `.ai/plan/fresh-session-continue-prompt.md`, `.ai/plan/next-agent-prompt.md`, `.ai/plan/handoff.md`, `.ai/plan/v2-roadmap.md`, `.ai/plan/packet.json`, `.ai/plan/packet.toon`, `.ai/plan/progress/upstream-remodex-watchlist-20260518.md`, `.ai/plan/progress/upstream-remodex-watchlist-20260518.toon`, `.ai/plan/current-owner.json`, `.ai/plan/current-audit.jsonl`.
- Validation: `handover_current.py audit` OK; `git diff --check` OK; upstream license/contributing details previously checked from Remodex `origin/main` at `603dfc5`.
- Open risks: Engineering-level OSS guidance only, not formal legal advice; check each new third-party dependency/binary before importing.

## 2026-05-18T06:53:34-04:00 | agent=codex | cli=codex | model=gpt-5 | task=upstream-remodex-watchlist-20260518
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: Record upstream/license/contribution decisions into handoff docs
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=1819124f393a4d95e7cd665c0f45f386d7a2b148ea77e6ecb8d474aa2f0f1ecf
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-17T22:59:43-04:00 | agent=codex | cli=codex | model=gpt-5 | task=upstream-remodex-watchlist-20260517
- TL;DR: Added upstream Remodex comparison recommendations to the future roadmap and refreshed current handoff with the post-merge baseline.
- Next action: Future feature iterations should read `.ai/plan/v2-roadmap.md` direction E before pulling upstream ideas; do not wholesale import upstream Terminal SSH/GhosttyKit.
- Scope / boundary: Docs only; no iOS/Bridge code change, no version/build bump, no tests, no worktree deletion.
- Changed files: `.ai/plan/v2-roadmap.md`, `.ai/plan/current.md`, `.ai/plan/fresh-session-continue-prompt.md`, `.ai/plan/next-agent-prompt.md`, `.ai/plan/handoff.md`.
- Validation: Upstream Remodex fetched and checked at `603dfc5`; local `LICENSE`/`NOTICE` and package license fields remain Apache-2.0.
- Open risks: Legal conclusion is engineering-level license hygiene, not formal legal advice; re-check third-party licenses before importing new vendor binaries or dependencies.

## 2026-05-16T23:29:04-04:00 | agent=codex | cli=codex | model=gpt-5 | task=fresh-session-style-unify-merge-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: New session should read fresh prompt, inspect dirty main and terminal-style-unify worktree, then commit small validated slices
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=c1ae33aeba8ae60738ded1eb5ee17a652bc6100545d2e2e3245d12d968fb63ed
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T23:28:55-04:00 | agent=codex | cli=codex | model=gpt-5 | task=fresh-session-style-unify-merge-20260516
- TL;DR: Refreshed fresh-session prompt for a new compact session; next work is dirty-main cleanup plus safe import of `.claude/worktrees/terminal-style-unify` changes.
- Next action: New session reads `.ai/plan/fresh-session-continue-prompt.md`, inspects main/worktree dirty diffs, commits small validated slices, then handles version/package sync.
- Scope / boundary: Docs/handoff only; no iOS code change, no version/build bump, no install, no tests.
- Changed files: `.ai/plan/fresh-session-continue-prompt.md`, `.ai/plan/next-agent-prompt.md`, `.ai/plan/current.md`, `.ai/plan/handoff.md`.
- Validation: prompt written; final `git diff --check` pending.
- Open risks: main is dirty; `feat/terminal-style-unify` branch has no new commit, only dirty worktree files; direct merge would miss changes.

## 2026-05-16T23:21:34-04:00 | agent=codex | cli=codex | model=gpt-5 | task=ios-swiftterm-ghost-multiagent-wait-20260516
- TL;DR: Multiagent results received and recorded; ghost remains unresolved but no longer blocks the whole v2 track.
- Next action: Continue v2 work unless user explicitly wants another dedicated ghost pass; if returning, start with SwiftTerm source-level visible-rect/row clear diagnostic and Bridge/iOS seq/hash tracing.
- Scope / boundary: Docs/handoff only; no iOS code change, no version/build bump, no install, no Xcode tests.
- Changed files: `.ai/plan/current.md`, `.ai/plan/handoff.md`, `.ai/plan/packet.json`, `.ai/plan/packet.toon`, `.ai/plan/progress/swiftterm-ghost-multiagent.md`, `Docs/swiftterm_ghost_analysis.md`.
- Validation: Both subagents completed; docs updated; `mms-toon --auto` regenerated packet; final syntax/audit checks pending.
- Open risks: SwiftTerm ghost root still needs a bounded evidence-backed patch; avoid replay/full-refresh, RunLoop/default-mode drain, hidden input proxy, SwiftTerm disable, and latest SwiftTerm upgrade without Metal Toolchain fix.

## 2026-05-16T23:20:17-04:00 | agent=codex | cli=codex | model=gpt-5 | task=ios-swiftterm-ghost-multiagent-wait-20260516
- TL;DR: User confirms SwiftTerm ghost/影子 still remains, but other regressions are resolved; stop local trial-and-error and keep this as a multiagent/source-level investigation.
- Next action: Wait for `Peirce` and `Kierkegaard` outputs or hand `.ai/plan/swiftterm-ghost-multiagent-prompt.md` to another agent; implement only an evidence-backed diagnostic/patch.
- Scope / boundary: Docs/handoff only in this slice; no iOS code change, no version/build bump, no install, no Xcode tests.
- Changed files: `.ai/plan/current.md`, `.ai/plan/handoff.md`, `.ai/plan/packet.json`, `.ai/plan/packet.toon`, `.ai/plan/progress/swiftterm-ghost-multiagent.md`.
- Validation: `wait_agent` on `019e33ec-f229-7f90-b8fa-766d3d859ac2` and `019e33ed-0b05-7fa0-97ff-feda2c0249aa` timed out after 120s with no final output; docs-only validation pending.
- Open risks: Ghost root remains unresolved; do not retry replay/full-refresh, RunLoop/default-mode drain, hidden input proxy, SwiftTerm disable, or latest SwiftTerm upgrade without Metal Toolchain fix.

## 2026-05-16T23:19:16-04:00 | agent=codex | cli=codex | model=gpt-5 | task=ios-swiftterm-ghost-multiagent-wait-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: Record user-confirmed ghost remains; wait for multiagent outputs before any more patches
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=49bd9ed9b0db9b869c8191b8803dc43b3a210a424a3fc9d9b6a3ca49d222975f
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T23:13:23-04:00 | agent=codex | cli=codex | model=gpt-5 | task=ios-swiftterm-ghost-escalation-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: Stop local trial-and-error; hand off unresolved SwiftTerm visual ghost to multiagent investigation.
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=23ba3f9ff37e435d14716996a08333030a33ccb716e7467a4258397fedb1924a
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T22:39:10-04:00 | agent=codex | cli=codex | model=gpt-5 | task=ios-terminal-live-only-20260516
- TL;DR: User screenshot showed remaining `replay` garble; corrected direction. Restarted Bridge daemon so JS stream fixes are live, then installed `1.7.52 build 90` with SwiftTerm stream `replay: false` to stop feeding `tmux capture-pane -e` rendered snapshots into SwiftTerm emulator.
- Next action: User force-close/reopen app, confirm `1.7.52/90`, and smoke SwiftTerm. Status should not show `replay`; test fresh `pwd`, `cd`, rapid typing.
- Scope / boundary: iOS SwiftTerm live-only stream start + Bridge daemon restart; SwiftTerm enabled; legacy Terminal fallback preserved; no Xcode tests; private relay endpoints not exposed in docs.
- Changed files: `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`, `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`, plus prior Bridge stream normalization files and handoff packet files.
- Validation: `git diff --check` OK; generic iOS Debug build OK; signed device Debug build OK with `HOME=/Users/xin`; device install OK; Info.plist confirms `1.7.52/90`; launch blocked only by locked phone. Prior Node full tests `329/329` OK.
- Open risks: If ghost remains without replay, collect screen recording/stream bytes and move to SwiftTerm source patch; do not retry RunLoop/default-mode drain or replay/full-screen flash.

## 2026-05-16T22:39:18-04:00 | agent=codex | cli=codex | model=gpt-5 | task=ios-terminal-live-only-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: User smoke 1.7.52/90 SwiftTerm live-only; status should not show replay
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=df35825a10e5227fcb6a292b203041205c7f736f765f26657c8026aa6f869069
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T22:32:10-04:00 | agent=codex | cli=codex | model=gpt-5 | task=ios-terminal-crlf-font-stabilize-20260516
- TL;DR: Installed `1.7.51 build 89` with Terminal stream newline normalization moved to Bridge once for both replay/live, duplicate adjacent CR collapsed, iOS SwiftTerm raw-feeding bytes, and SwiftTerm font reset avoided on every update.
- Next action: User smoke `1.7.51/89`; verify `pwd`, `cd`, rapid typing, and whether original visual ghost remains.
- Scope / boundary: Bridge Terminal stream normalization + iOS SwiftTerm feed/font stabilization only; SwiftTerm enabled; legacy Terminal fallback preserved; no Xcode tests; private relay endpoints not exposed.
- Changed files: `mms-remote-bridge/src/tmux-control-adapter.js`, `mms-remote-bridge/src/terminal-stream-hub.js`, `mms-remote-bridge/test/tmux-control-adapter.test.js`, `mms-remote-bridge/test/terminal-stream-hub.test.js`, `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`, `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`, handoff packet files.
- Validation: local tmux replay/live probe shows no bare LF/CRCRLF; Node full tests `329/329` OK; generic iOS Debug build OK; signed device build OK with `HOME=/Users/xin`; device install OK; app launch blocked only by locked phone.
- Open risks: If ghost remains after stream correctness fix, collect screen recording/stream bytes before further SwiftTerm renderer changes; do not retry RunLoop/default-mode drain.

## 2026-05-16T22:32:05-04:00 | agent=codex | cli=codex | model=gpt-5 | task=ios-terminal-crlf-font-stabilize-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: User smoke 1.7.51/89 cd/pwd and SwiftTerm ghost after Bridge CRLF normalization
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=8dfc3b1aa341fe3b3fc72a4d8da878d50989bac53717117dbb11388ce5d2507b
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T22:12:03-04:00 | agent=codex | cli=codex | model=gpt-5 | task=ios-terminal-runloop-redraw-20260516
- TL;DR: User showed `1.7.49/87` was worse (`cd`/`pwd` echo/order broken). Reverted RunLoop stream drain + row-level redraw and installed `1.7.50 build 88` with direct `feedPreservingScroll` restored.
- Next action: User smoke `1.7.50/88`; confirm `1.7.49` regression gone. If ghost remains, switch to telemetry/local SwiftTerm patch, not wrapper timing hacks.
- Scope / boundary: iOS SwiftTerm rollback/restore only; SwiftTerm enabled; legacy Terminal fallback preserved; no Xcode tests; private relay endpoints not exposed.
- Changed files: `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`, `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`, handoff packet files.
- Validation: `git diff --check` OK; generic iOS Debug build OK; signed device Debug build OK; device install OK; Info.plist confirms `1.7.50/88`.
- Open risks: Original ghost likely still needs SwiftTerm-level patch or targeted telemetry; do not retry RunLoop/default-mode drain.

## 2026-05-16T22:03:39-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-runloop-redraw-20260516
- TL;DR: Installed `1.7.49 build 87`; remaining SwiftTerm iOS ghost now addressed via RunLoop/default-mode stream drain + previous/current cursor-row invalidation, not replay/full-screen flash.
- Next action: User smoke `1.7.49/87`; verify rapid typing/scroll-output no longer leaves persistent visual ghost and no obvious input latency.
- Scope / boundary: iOS SwiftTerm renderer mitigation only; SwiftTerm enabled; legacy Terminal fallback preserved; private relay endpoints not exposed; no Xcode tests.
- Changed files: `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`, `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`, handoff packet files.
- Validation: `git diff --check` OK; generic iOS Debug build OK after removing non-open `draw(_:)` override; signed device Debug build OK; device install OK.
- Open risks: If ghost persists, consider local SwiftTerm backport of #498/#526 without Metal or add targeted telemetry for `contentOffset`/cursor row/stream batch timing.

## 2026-05-16T22:00:12-04:00 | agent=codex | cli=codex | model=gpt-5 | task=ios-terminal-runloop-redraw-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: Implement RunLoop stream drain and row-level cursor redraw for SwiftTerm ghost
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=82433aace0b94cc1fa18951b3f168c6459ebca2bebd882fe92cadebbccc31f83
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T21:44:30-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-swiftterm-upstream-ghost-fix-20260516
- TL;DR: User reported ghost still persisted; web/upstream research found SwiftTerm PR #488 matching exact iOS ghost mechanism. Installed `1.7.48 build 86` pinned to SwiftTerm commit `9ad1b19` containing the fix.
- Next action: User smoke `1.7.48/86`; verify SwiftTerm typing no longer leaves visual ghost, especially after scroll/output updates.
- Scope / boundary: SwiftTerm dependency pin + no-flash renderer fix path; SwiftTerm enabled; legacy fallback preserved; no Xcode tests; no private relay endpoint exposure.
- Changed files: `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`, `CodexMobile/CodexMobile.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`, `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`, handoff packet files.
- Validation: `git diff --check` OK; targeted Node stream suite 6/6 OK; package resolve to SwiftTerm `9ad1b19` OK; iOS generic Debug build OK; signed device build OK; device install OK.
- Open risks: `v1.13.0` includes same fix but requires MetalToolchain in current Xcode; pinned exact commit avoids that. If ghost remains, collect recording/evidence before more patches.


## 2026-05-16T21:40:01-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-atomic-redraw-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: User smoke 1.7.48/86 SwiftTerm visual ghost after atomic viewport redraw
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=9a9ed2284e6c05e6e88208a6a891c474e1f388a828a5717702e9c851c99b88c7
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T21:29:18-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-cursor-cell-invalidate-20260516
- TL;DR: User reported `1.7.45/83` still had ghost; installed `1.7.46 build 84` with previous/current full cursor-cell invalidation, not just cursor-bar redraw.
- Next action: User smoke `1.7.46/84`; if ghost remains, capture duplicate `terminal/input`/output evidence before more visual patches.
- Scope / boundary: SwiftTerm low-flash redraw fix only; SwiftTerm enabled; legacy Terminal fallback preserved; no Xcode tests; no private relay endpoint exposure.
- Changed files: `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`, `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`, handoff packet files.
- Validation: `git diff --check` OK; targeted Node stream suite 6/6 OK; iOS generic Debug build OK; signed device build OK; device install OK.
- Open risks: If ghost persists, likely not native caret alone; next path is duplicate input/output diagnostics or SwiftTerm draw internals.

## 2026-05-16T21:29:18-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-cursor-cell-invalidate-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: User smoke 1.7.46/84 precise cursor-cell invalidation
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=e64f96257f1f59e8e77bdc87796d26262b43c027fbac7ca7a87365b21135ae5c
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T21:15:31-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-caretview-ghost-20260516
- TL;DR: Read `Docs/swiftterm_ghost_analysis.md`; agreed root likely SwiftTerm native `CaretView` re-add race. Installed `1.7.45 build 83` with `addSubview` interception so native `CaretView` never enters hierarchy.
- Next action: User opens app manually and smokes `1.7.45/83`: verify SwiftTerm input has no ghost and no replay/full-refresh flash.
- Scope / boundary: SwiftTerm ghost root fix only; SwiftTerm stays enabled; legacy Terminal fallback preserved; no Xcode tests; no private relay endpoint exposure.
- Changed files: `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`, `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`, handoff packet files.
- Validation: `git diff --check` OK; targeted Node stream suite 6/6 OK; generic iOS build initially failed because `draw(_:)` override is non-open, then passed after removal; signed device build OK; device install OK after tunnel retry; launch blocked by CoreDevice tunnel disconnect.
- Open risks: If ghost persists, inspect duplicate `terminal/input`; if input single, consider local SwiftTerm patch for dirty-rect/caret internals.

## 2026-05-16T21:15:31-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-caretview-ghost-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: User smoke 1.7.45/83 SwiftTerm ghost after CaretView addSubview block
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=4b064658b302c2e6cbd5bb1ff2e611480e459329d1a768c3f1d23f195696f0bd
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T21:02:43-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-no-flash-root-20260516
- TL;DR: Installed `1.7.44 build 82`; removed the visible post-input refresh path by keeping replay disabled and dropping immediate/full redraws from normal SwiftTerm echo handling.
- Next action: User unlocks/opens app and smokes `1.7.44/82`: verify SwiftTerm input has no persistent double-character and no per-key flash.
- Scope / boundary: iOS SwiftTerm render/input mitigation only; SwiftTerm remains enabled; legacy Terminal fallback preserved; no Xcode tests; private relay endpoints not documented.
- Changed files: `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`, `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`, `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`, handoff packet files.
- Validation: `git diff --check` OK; targeted Node stream suite 6/6 OK; iOS generic Debug build OK; signed device build OK; `devicectl` install OK after retry; `devicectl` launch blocked because phone was locked. Xcode tests not run by rule.
- Open risks: If ghost returns without flash, inspect duplicate `terminal/input` vs SwiftTerm/UIKit cell invalidation; do not disable SwiftTerm or reintroduce replay-only masking as final fix.

## 2026-05-16T21:02:35-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-no-flash-root-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: User smoke 1.7.44/82 SwiftTerm input; if phone is unlocked, launch com.mms.remote or user opens app manually
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=97e6c117956845a4d29bd4174672688232ca061609f691d0834a36cbb548f486
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T12:33:57-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-double-char-root-20260516
- TL;DR: Installed `1.7.42 build 80`; `1.7.41/79` replay cleanup worked, then `1.7.42/80` added duplicate SwiftTerm stream-start guard so Terminal entry opens one stream instead of two.
- Next action: User smoke `1.7.42/80`: verify SwiftTerm input has no persistent double-character/ghost; if it remains, inspect duplicate input/resize logs.
- Scope / boundary: iOS SwiftTerm lifecycle/input mitigation + Bridge stream replay dedupe already loaded by local Bridge restart; no Xcode tests; legacy Terminal fallback preserved; private relay endpoints not documented.
- Changed files: `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`, `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`, `mms-remote-bridge/src/terminal-stream-hub.js`, `mms-remote-bridge/test/terminal-stream-hub.test.js`, `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`, handoff packet files.
- Validation: `git diff --check` OK; targeted Node stream suite 6/6 OK; iOS generic Debug build OK; signed device build OK; `devicectl` install OK; `devicectl` launch OK. Xcode tests not run by rule.
- Open risks: `terminal/resize`/`terminal/input` still show duplicate log lines; if visual issue persists, debug that path, not SwiftTerm disable.

## 2026-05-16T12:33:13-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-double-char-root-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: User smoke 1.7.42/80 SwiftTerm input; if ghost remains, inspect duplicate input path
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=dbb31cce0a9d17216ae116998746fb2164853a18fe216d37f358b2f5b373e44d
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T12:15:58-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-caret-stream-dedupe-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: User smoke 1.7.40/78 SwiftTerm input ghost/double-char
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=dbb31cce0a9d17216ae116998746fb2164853a18fe216d37f358b2f5b373e44d
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T12:04:51-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-caret-overlay-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: User smoke 1.7.38 build 76 for SwiftTerm caret overlay ghost fix
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=dbb31cce0a9d17216ae116998746fb2164853a18fe216d37f358b2f5b373e44d
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T11:35:45-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-hidden-input-proxy-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: Implement hidden input proxy for SwiftTerm, bump to 1.7.35/73, build/install on song iPhone, update handoff.
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=dbb31cce0a9d17216ae116998746fb2164853a18fe216d37f358b2f5b373e44d
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T11:30:07-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-swiftterm-restore-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: Smoke 1.7.34 build 72: SwiftTerm restored, double-character shadow, create sheet
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=dbb31cce0a9d17216ae116998746fb2164853a18fe216d37f358b2f5b373e44d
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T11:28:56-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-swiftterm-restore-20260516
- TL;DR: Corrected the wrong mitigation: SwiftTerm is enabled again in `1.7.34 build 72`; removed the local post-input reset hack and replaced it with debounced authoritative stream replay after SwiftTerm input.
- Next action: User smoke on phone: confirm `1.7.34/72`, SwiftTerm is active/available, double-character shadow self-cleans without tab switch, and Terminal `+` create sheet still works.
- Scope / boundary: SwiftTerm restore + input-shadow mitigation + build bump; no Xcode tests; no Bridge management; Stable renderer and legacy Terminal fallback preserved.
- Changed files: `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`, `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`, plus handoff packet files.
- Validation: `git diff --check` OK; iOS generic Debug build OK; signed device build OK; `devicectl` install OK; `devicectl` launch OK. Xcode tests not run by rule.
- Open risks: If shadow remains, fix root cause next (SwiftTerm input subclass or tmux stream dedupe); do not disable SwiftTerm again as a fake fix.

## 2026-05-16T11:22:44-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-stable-create-relay-guard-20260516
- TL;DR: Installed `1.7.33 build 71` with Terminal Stable renderer forced by default, SwiftTerm live renderer disabled due to double-character/shadow repro, Stable dark text readability patched, and Terminal create flow changed to a sheet with Mac folder picker + per-create visible-terminal options.
- Next action: User smoke on phone: confirm version/build, no double characters in Terminal, dark text visible, `+` opens create sheet, folder browser fills cwd, and per-create Mac visible terminal toggle/app work.
- Scope / boundary: iOS Terminal UX/renderer mitigation + V2/public relay guard docs; no Xcode tests; no Bridge management; legacy Terminal fallback preserved; private relay domains not written to public docs/code.
- Changed files: `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`, `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`, `CodexMobile/CodexMobile/Views/Terminal/StableTerminalSnapshotTextView.swift`, `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`, `.ai/plan/v2-roadmap.md`, `.ai/plan/current.md`, `.ai/plan/handoff.md`, `.ai/plan/packet.json`, `.ai/plan/packet.toon`, `.ai/plan/next-agent-prompt.md`, `.ai/plan/fresh-session-continue-prompt.md`.
- Validation: `git diff --check` OK before docs refresh; iOS generic Debug build OK; signed device build OK; `devicectl` install OK; `devicectl` launch OK. Xcode tests not run by rule.
- Open risks: SwiftTerm live renderer is disabled, not fixed; if user still sees double characters, verify installed `1.7.33/71` and whether they are on Stable vs legacy Terminal; relay public-release guard must be enforced in release/review packaging.

## 2026-05-16T11:22:33-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-stable-create-relay-guard-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: Smoke 1.7.33 build 71 on song iPhone; verify Stable Terminal no double characters and + opens create sheet
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=a70dcaed7c08a4e16523b9bc65bc823794cb9efc927c8f715d2f215f9e2c4ff4
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T05:51:00-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=mms-remote-handoff-20260516
- TL;DR: Refreshed project-level handoff after latest stable `1.7.26 build 62`, documenting completed Terminal/Codex/sidebar iterations, current baseline, risks, validation, and future roadmap.
- Next action: Fresh session read `.ai/plan/mms-remote-project-handoff-20260516.md`, then continue user smoke feedback or low-risk `Docs/terminal_health_check.md` tasks.
- Scope / boundary: Docs/handoff only; no product code, no Bridge management, no Xcode tests, no device install.
- Changed files: `.ai/plan/mms-remote-project-handoff-20260516.md`, `.ai/plan/current.md`, `.ai/plan/handoff.md`, `.ai/plan/packet.json`, `.ai/plan/packet.toon`, `.ai/plan/fresh-session-continue-prompt.md`, `.ai/plan/next-agent-prompt.md`, `.ai/plan/current-owner.json`, `.ai/plan/current-audit.jsonl`.
- Validation: `packet.json` parsed; `packet.toon` generated with `mms-toon --auto`; `handover_current.py --root . audit` OK; `git diff --check` OK.
- Open risks: latest `1.7.26 build 62` still needs user smoke confirmation; unrelated `.ai/exec/`, `p184-*`, `.omc/`, and `tmp/` artifacts remain out of scope.

## 2026-05-16T05:45:11-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=mms-remote-handoff-20260516
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: Fresh session read .ai/plan/mms-remote-project-handoff-20260516.md, then continue post-1.7.26 validation and next Terminal/Codex iteration.
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=0ae653ac26856efbd21c74c63d9bcb4a95f3b12446d85f947eafee9826cc79d5
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-16T09:24:26Z | agent=Codex | cli=codex | model=gpt-5.5 | task=P184 MMSChat fresh handover
- TL;DR: Added MMSChat fresh-session handover and executor pack context. Current main Terminal/SwiftTerm work remains preserved.
- Next action: Run `/executor s184-0-mmschat-phase0-s0-s3 1cc3ceab49a2b2e2c32802968073d25a26cb347e executor=<model-id>` only for Phase0 S0/S3 evidence.
- Scope / boundary: No product code, no worktree, no live Claude/provider/send-keys probes, no deploy/push/global/destructive.
- Changed files: `.ai/plan/p184-mmschat-fresh-session-handover.md`, `.ai/plan/p184-mmschat-fresh-session-handover.json`, `.ai/plan/p184-mmschat-continue-prompt.md`, `.ai/plan/progress/mmschat-p184-status.md`.
- Validation: JSON parse, TOON generation, `git diff --check`.


## 2026-05-15T21:20:00-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=swift-terminal-polish-v2
- TL;DR: Created executable handbook for next session: compact chord UI, Swift tab theme/style fixes, and bottom Settings tab.
- Next action: Read `.ai/plan/swift-terminal-polish-handbook.md`, implement, bump to `1.7.5 build 41`, validate Node/iOS/device deploy.
- Scope / boundary: Do not disturb existing `Terminal/CLI`; Swift stable renderer remains default; avoid global style hacks that bleed across tabs.
- Changed files: `.ai/plan/swift-terminal-polish-handbook.md`, `.ai/plan/current.md`, `.ai/plan/handoff.md`, `.ai/plan/packet.json`, `.ai/plan/packet.toon`.
- Validation: Handoff only; previous slice validated Node `19/19`, iOS generic build, device deploy/launch for `1.7.4 build 40`.
- Open risks: tmux may not support every `C-M-symbol`; theme changes can bleed if implemented with global appearance or `.preferredColorScheme`.

## 2026-05-15T21:29:56-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=swift-terminal-polish-v2
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: New session implement compact chord UI, theme isolation, and Settings tab; then build/deploy with build bump.
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=53991cb9e909760b37b7d0e6463a7e3dbbf914301bb4a1fd7c774d85c893f774
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-15 10:32 -0400 — SwiftTerm Phase 6 P1 Blockers Fixed

- agent: Codex
- CLI: codex
- model: GPT-5
- task_id: ios-swiftterm-phase6-p1-fix
- status: P1 fixes applied; targeted Node suite and iOS build passed; version 1.6.2 build 25 installed, launch blocked by locked iPhone
- next_action: unlock iPhone, launch version 1.6.2 build 25 manually, then run `.ai/plan/swiftterm-phase6-checklist.md` visual matrix

### TL;DR

The Phase 6 SwiftTerm stream experiment is no longer blocked by the two P1 code findings. Streams are cleaned up on Swift tab/page/app/connection teardown, Bridge drops all streams on relay close/shutdown, and replay now buffers live output until after `replayEnd`, including pre-`replayStart` output emitted immediately after control stream attach.

### Changed Files

- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`
  - stops active stream on disappear/background/offline and guards start by active scene phase.
- `CodexMobile/CodexMobile/ContentView.swift`
  - stops all tracked terminal streams when switching away from the `Swift` tab.
- `CodexMobile/CodexMobile/Services/CodexService+Terminal.swift`
  - added `stopAllTerminalStreams()` and `clearTerminalStreamState()`.
- `CodexMobile/CodexMobile/Services/CodexService+Connection.swift`
  - clears stream state on disconnect / receive-error cleanup.
- `mms-remote-bridge/src/terminal-stream-hub.js`
  - added `stopAll()` and replay buffering for live output before/during replay.
- `mms-remote-bridge/src/terminal-hub.js`
  - exports `stopAllStreams` and accepts typo-compatible `terminal/stre/*` aliases.
- `mms-remote-bridge/src/bridge.js`
  - stops all terminal streams on relay disconnect and bridge shutdown.
- `mms-remote-bridge/test/terminal-stream-hub.test.js`
  - covers replay interleaving, pre-replay live buffering, and `stopAll()` cleanup.

### Validation

- Passed: targeted Bridge terminal Node suite 45/45.
- Passed: generic iOS Debug build.
- Passed: build/sign/install of version `1.6.2` build `25` on `song的iPhone`.
- Blocked: launch denied because the iPhone was locked; manual visual matrix still pending.
- Runtime: latest Bridge is running in tmux session `mms-remote-swiftterm-bridge` on port `9000`; capture QR with `tmux capture-pane -pt mms-remote-swiftterm-bridge:0 -S -80`.

### Residual Gate

`Swift` as a third visible tab is still a Phase 6 lab affordance only. Final product shape should be `Chats` / `Terminal`, with SwiftTerm hidden behind a dev flag or selected as a Terminal renderer mode.

## 2026-05-15 20:10 +0800 — Stable Baseline Confirmed Before SwiftTerm Stream Work

- agent: Codex
- CLI: codex
- model: GPT-5
- task_id: ios-terminal-swiftterm-plan-review
- status: user-confirmed current project state is stable; preserve as rollback baseline
- next_action: review `swiftterm-terminal-execution-plan.md`, then implement only gated protocol/stream slices

### TL;DR

Current local worktree is the stable baseline for upcoming SwiftTerm work. Keep bottom `Chats` / `Terminal` tabs, stable snapshot fallback, direct tmux input, and lazy Terminal tab initialization intact. Do not re-enable SwiftTerm as default until real byte streaming works.

### Baseline Rules

- Preserve stable fallback renderer and `terminal.experimentalSwiftTermRenderer` off/default-disabled behavior.
- Do not feed full `capture-pane` snapshots into SwiftTerm as the normal renderer.
- Keep `Terminal` as a sibling Bottom Tab Bar product, not Chat toolbar UI.
- Treat existing dirty worktree edits as user/active-session state; do not revert unrelated files.
- Do not run Xcode tests unless user explicitly asks.

## 2026-05-15 19:16 +0800 — Startup Crash Mitigation

- agent: Codex
- CLI: codex
- model: GPT-5
- task_id: ios-startup-crash-mitigation
- status: build 16 installed on connected iPhone; launch verification blocked by locked device
- next_action: unlock phone, launch build 16, then verify app opens Chat first and Terminal tab only initializes after tapping Terminal

### TL;DR

User reported app crash on entry. `devicectl --console` reproduced the previous installed build terminating with `signal 11` right after pairing/sync. Latest code was installed as build 15, then a lazy Terminal tab mitigation was added and installed as build 16.

### Changed Files

- `CodexMobile/CodexMobile/ContentView.swift`
  - Terminal tab now uses `terminalTabBody`.
  - `TerminalHubView` is only constructed when `selectedAppTab == .terminal`.
  - This avoids eager Terminal initialization during app startup/Chat sync.
- `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`
  - device deploy script bumped `CURRENT_PROJECT_VERSION` from 14 -> 15 -> 16 during installs.

### Validation

- Passed: generic iOS build after lazy tab change.
- Passed: signed device build/install via `./CodexMobile/scripts/deploy-ios-device.sh --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 --no-launch`.
- Blocked: `devicectl device process launch --console` after install because iPhone was locked.

## 2026-05-15 19:02 +0800 — Terminal Foundation Stabilized

- agent: Codex
- CLI: codex
- model: GPT-5
- task_id: ios-terminal-foundation-stabilize
- status: stable fallback patched; simulator build, generic iOS device build, and terminal Node tests passed
- next_action: install on phone and verify terminal output/input behavior before any further SwiftTerm work

### TL;DR

User rejected current Terminal UI: horizontal scrolling, centered/broken viewport, bad input, and missing glyph boxes. This patch stops the fake-polish path and stabilizes the base terminal surface.

### Changed Files

- `CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift`
  - no horizontal scroll in terminal output.
  - selected pane shown as a fixed summary + menu picker instead of scrollable chips.
  - quick keys wrap in a grid instead of horizontal scroll.
  - experimental SwiftTerm snapshot renderer is hard-disabled for now.
  - stable snapshot requests visible viewport only.
  - stable renderer resizes tmux to phone viewport.
  - terminal text is left/top anchored, soft-wrapped, and strips unsupported private-use glyphs.
  - input field sends edits directly to tmux; Enter sends Enter instead of resending a full command line.
- `CodexMobile/CodexMobile/Services/LocalizationManager.swift`
  - fixed one missing comma in the Chinese string table.

### Why

- `ScrollView([.vertical, .horizontal])` plus `fixedSize(horizontal: true)` caused left clipping and sideways terminal drift.
- Full scrollback snapshots made the visible output feel centered/random instead of a terminal viewport.
- SwiftTerm fed with `capture-pane` snapshots is not a real terminal; keep it off until stream/control-mode exists.
- iOS system mono fonts lack many Nerd Font / PUA symbols; strip them rather than show boxes.

### Validation

- Passed: `xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/DerivedData build CODE_SIGNING_ALLOWED=NO`.
- Passed: `xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData-device build CODE_SIGNING_ALLOWED=NO`.
- Passed: `node --test mms-remote-bridge/test/terminal-hub.test.js mms-remote-bridge/test/terminal-visible-launcher.test.js mms-remote-bridge/test/mms-remote-cli.test.js` => 34/34.
- Xcode tests not run per project rule.

## 2026-05-15 18:16 +0800 — Localization Guardrails Added

- agent: Codex
- CLI: codex
- model: GPT-5
- task_id: ios-localization-guardrails
- status: docs-only constraint update; build fix intentionally left to active implementation agent
- next_action: finish current Swift build work, then verify device build without adding ad-hoc localization overloads

### TL;DR

Direction is correct: `Chats` / `Terminal` split remains the product path, and multilingual UI support is worth keeping. Current build noise appears tied to localization implementation details, not the product direction.

### Constraints Added

- New user-facing iOS text must be localizable from first implementation.
- Every new visible string needs `zh-Hans` and `en` entries.
- Keep technical terms in English: `Codex`, `Terminal`, `tmux`, `Bridge`, `iTerm2`, `Ghostty`, `SwiftTerm`, `QR`.
- Use one shared localization layer; avoid ad-hoc SwiftUI overloads like `navigationTitle(localized:)` / `Label(localized:)`.
- Include navigation titles, alerts, labels, buttons, placeholders, empty states, and accessibility labels.
- Exempt developer logs, comments, tests, and protocol constants.

### Changed Files

- `AGENTS.md`
- `CLAUDE.md`
- `.ai/plan/next-agent-prompt.md`
- `.ai/plan/handoff.md`

### Validation

- Docs-only change.
- No build or tests run; user asked to ignore current multilingual build issue while another agent continues implementation.

## 2026-05-15 18:11 +0800 — SwiftTerm Snapshot Fallback Rescue

- agent: Codex
- CLI: codex
- model: GPT-5
- task_id: ios-terminal-swiftterm-snapshot-rescue
- status: rescue applied; Node tests and iOS Debug build passed
- next_action: install/phone-verify stable fallback, then redesign SwiftTerm around stream/control-mode before default enable

### TL;DR

User installed latest build and reported severe lag, no visible space echo, no cursor. Diagnosis: current SwiftTerm path was not a real terminal connection; it repeatedly fed `tmux capture-pane` snapshots into SwiftTerm. That loses cursor/input state and forces expensive reset/feed cycles. Disabled SwiftTerm snapshot renderer by default; restored stable Text snapshot + command input path.

### Changed Files

- `CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift`
  - added `@AppStorage("terminal.experimentalSwiftTermRenderer")`, default `false`.
  - default renderer is stable snapshot `Text` view again.
  - restored command input bar so space/typing is visible before send.
  - kept SwiftTerm path as experimental only.
  - paste appends to command draft in stable mode; copy copies snapshot text.
- `CodexMobile/CodexMobile/Services/CodexService+Terminal.swift`
  - `refreshTerminalSnapshot` now supports optional `preserveAnsi`, `joinWrapped`, `viewportOnly`.
  - stable path avoids ANSI/viewport options; experimental SwiftTerm path requests them.
- `CodexMobile/CodexMobile/Views/Home/HomeEmptyStateView.swift`
  - fixed remaining invalid `navigationTitle(localized:)`.

### Why Previous Approach Was Wrong

- `capture-pane` snapshot is a rendered text capture, not a PTY stream.
- It does not preserve live cursor semantics.
- Resetting SwiftTerm and feeding the whole snapshot causes jank on phone.
- Input cannot feel instant because there is no local terminal echo; UI waits for tmux snapshot refresh.

### Correct Future Direction

- SwiftTerm default only after a real output stream exists.
- Explore tmux control mode, `%output`, or `pipe-pane` + viewport/state protocol.
- Renderer should receive terminal byte stream + resize events, not repeated full text screenshots.

### Validation

- Passed: `node --test mms-remote-bridge/test/terminal-hub.test.js mms-remote-bridge/test/terminal-visible-launcher.test.js mms-remote-bridge/test/mms-remote-cli.test.js` => 34/34.
- Passed: `xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/DerivedData build CODE_SIGNING_ALLOWED=NO` => `BUILD SUCCEEDED`.
- Xcode tests not run per project rule.

## 2026-05-15 17:46 +0800 — Terminal-First Product Split

- agent: Codex
- CLI: codex
- model: GPT-5
- task_id: ios-terminal-tabbar-product-split
- status: product structure changed; Node tests and iOS Debug build passed
- next_action: phone-verify Tab Bar split, then continue SwiftTerm terminal input/rendering polish

### TL;DR

Decision: choose `A. Bottom Tab Bar`. MMS Remote should present `Chats` and `Terminal` as sibling products. Terminal must stop living as a toolbar-launched Chat subfeature.

### Scope / Boundary

- In scope: root product navigation, Chat/Terminal separation, handoff docs, next-agent direction.
- Out of scope in this slice: finishing SwiftTerm renderer, redesigning full terminal keyboard, committing/pushing.
- Preserve local-first bridge/QR/tmux workflow.
- Do not revert other uncommitted SwiftTerm/tmux work in this worktree.

### Changed Files

- `CodexMobile/CodexMobile/ContentView.swift`
  - added root `TabView` with `Chats` and `Terminal`.
  - Chat keeps sidebar/TurnView/home stack.
  - Terminal owns independent `NavigationStack`.
  - removed Chat toolbar Terminal shortcut.
  - tab switch to Terminal dismisses Chat drawer/search/keyboard.
- `CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift`
  - made `onClose` optional.
  - independent Terminal tab hides old `Chats` return button.
- `.ai/plan/current.md`
  - updated current truth, product decision, wrong directions, must-fix list.
- `.ai/plan/handoff.md`
  - prepended this entry.
- `.ai/plan/packet.json`
  - new machine-readable packet for next agent.
- `.ai/plan/packet.toon`
  - compact agent-facing packet generated from `packet.json`.
- `CodexMobile/CodexMobile/Services/LocalizationManager.swift`
  - fixed invalid `Label(localized:)` call.
- `CodexMobile/CodexMobile/Views/SettingsView.swift`
  - fixed invalid `navigationTitle(localized:)` calls.
- `CodexMobile/CodexMobile/Views/Sidebar/ArchivedChatsView.swift`
  - fixed invalid `navigationTitle(localized:)` call.

### Product Direction

Correct:

- Bottom Tab Bar as long-term default.
- SwiftTerm as terminal renderer.
- Terminal-specific keyboard and settings inside Terminal.
- Chat as lightweight Codex companion, not full desktop clone.

Wrong / must stop:

- stuffing Terminal into Chat toolbar.
- adding endless shortcut buttons as the main keyboard model.
- treating snapshot/poll text rendering as final terminal UX.
- copying full Codex App surface area.

### Validation

- Passed:

```bash
cd /Users/xin/auto-skills/CtriXin-repo/mms-remote
node --test mms-remote-bridge/test/terminal-hub.test.js mms-remote-bridge/test/terminal-visible-launcher.test.js mms-remote-bridge/test/mms-remote-cli.test.js
xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/DerivedData build CODE_SIGNING_ALLOWED=NO
```

- Node result: 34/34 pass.
- iOS build result: `BUILD SUCCEEDED`.

### Risks

- Worktree has active edits from another agent: SwiftTerm, terminal bytes input, resize, settings, tests.
- SwiftTerm package/project wiring may still fail build.
- Tab Bar costs vertical space; Terminal key bar should become compact/hideable.

## 2026-05-15T17:45:51+08:00 | agent=Codex | cli=codex | model=GPT-5 | task=ios-terminal-tabbar-product-split
- TL;DR: Claimed top-level `current.md` ownership.
- Next action: verify tab split, continue SwiftTerm terminal input polish
- Scope / boundary: Only this owner should overwrite `current.md`; side sessions should write `progress/<task-id>.md`.
- Validation: current_sha_at_claim=d1cb19c3bb2f544ab3c26ceba59f5d3fa15c7f520e7049adf425a7ae57034ba9
- Risk: If audit reports conflict, inspect `handoff.md` before continuing.

## 2026-05-15 16:47 +0800 — Main Adopted Running Terminal Branch

- agent: Codex
- CLI: codex
- model: GPT-5
- task_id: main-adopt-ios-terminal-running-branch
- status: merged to `main`; branch-wins merge complete
- next_action: continue from `main`, clean runtime verify, then integrate SwiftTerm renderer

### TL;DR

`main` now contains the user-tested running terminal branch. Merge commit: `98072a8 merge: adopt ios terminal running branch`. Source commit: `b7196688f9c26c9ed23407d8fd19c00143a0255f`. Old main was preserved at `codex/backup-main-before-ios-terminal-merge-20260515`.

### Merge Rule Used

Branch wins. During merge conflicts, main tree was reset to `b7196688...` so failed rescue code from old main does not remain mixed into the final code tree. Treat `main` as the source of truth for future agents.

### Next Agent Prompt

Use `.ai/plan/next-agent-prompt.md`.

## 2026-05-15 16:34 +0800 — iOS Terminal Running Branch

- agent: Codex
- CLI: codex
- model: GPT-5
- task_id: ios-terminal-running-branch
- status: ready for merge after user phone verification and local build/test pass
- next_action: merge this branch as code truth, then run clean bridge + real phone acceptance

### TL;DR

Use `/Users/xin/auto-skills/CtriXin-repo/mms-remote-ios-22e6243` on branch `codex/ios-remote-22e6243` as the current running Terminal branch. User confirmed the previous persistent phone `Terminal Error` is gone. This iteration also fixes Ghostty/iTerm visible-open behavior and improves the stopgap iOS terminal viewer.

### Scope / Boundary

- In scope: tmux-managed panes, iOS terminal list/snapshot/input/create/close, visible Mac terminal open, local bridge runtime.
- Out of scope until renderer phase: exact Ghostty/iTerm-level terminal emulation, ANSI grid, alternate screen, mouse, full Nerd Font glyph fidelity.

### Changed Files

- `CodexMobile/CodexMobile/Services/CodexService+Terminal.swift`
- `CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift`
- `CodexMobile/CodexMobile/Models/TerminalModels.swift`
- `mms-remote-bridge/src/terminal-visible-launcher.js`
- `mms-remote-bridge/test/terminal-visible-launcher.test.js`
- `PLAN.md`
- `.ai/plan/current.md`
- `.ai/plan/handoff.md`

### Validation

- Targeted Bridge tests passed: `node --test test/terminal-visible-launcher.test.js test/terminal-hub.test.js test/mms-remote-cli.test.js` => 32/32.
- iOS Debug simulator build succeeded with `xcodebuild ... build`.
- Earlier full `npm test` result: 307/308 pass; only existing `bridge-desktop-ipc-integration.test.js` wait timed out.

### Remaining Renderer Plan

The screenshots show line/glyph issues because current iOS viewer is still `SwiftUI Text`, not a terminal emulator. Stopgap now prevents wrapping and hides unsupported PUA glyph boxes. Real parity should use SwiftTerm native renderer first; xterm.js in WKWebView remains fallback.

### Next Task: SwiftTerm Renderer

- Integrate SwiftTerm first. Treat xterm.js/WKWebView only as fallback.
- Keep aesthetics as a release requirement: polished dark terminal, stable monospace metrics, no visibly broken separator/prompt layout.
- Bridge likely needs richer terminal stream/snapshot semantics after renderer lands: preserve ANSI (`capture-pane -e`), size negotiation, resize on view geometry, and possibly incremental output instead of plain text snapshots.
- Start behind a feature flag or fallback path so existing Terminal controls still work if SwiftTerm integration regresses.

Acceptance:
- Claude/Codex prompt blocks, separators, progress bars, and CJK text align on phone.
- ANSI color, cursor movement, clear screen, prompt editing, and common full-screen apps render far better than the SwiftUI `Text` view.
- No "ugly but technically works" final state; if native renderer is incomplete, keep fallback clearly marked.

### TODO: Visible Terminal Preference

- Add iOS preference for Mac visible terminal app: `auto`, Ghostty, iTerm2, Terminal.app.
- Current default remains `auto`: Ghostty -> iTerm2 -> Terminal.app.
- Future UI location: Terminal settings first; optional per-create/per-open override later.
- Bridge already accepts visible app values through `MMS_REMOTE_VISIBLE_TERMINAL` and RPC params; likely work is mostly iOS preference plumbing + small create/open UI.

## 2026-05-15 04:15 -0400 — Terminal Rescue Pause

- agent: Codex
- CLI: codex
- model: GPT-5
- task_id: terminal-rescue-handoff
- status: paused; user will merge a working branch from another worktree
- next_action: inspect merged branch, verify clean runtime, then continue only from evidence

### TL;DR

The project goal is still a phone-controlled tmux Terminal alongside Codex Chat. Current `main` has several terminal recovery commits but user reports the feature remains broken. Stop patching current assumptions. Use the user-provided working branch as the new truth, compare it to known-good `3fa85e4`, then resume in small validated slices.

### Scope / Boundary

- In scope: tmux-managed panes, iOS terminal list/snapshot/input/create/close, `mmr join`, Bridge terminal RPC, relay pairing.
- Out of scope for MVP: automatic capture of arbitrary non-tmux Terminal.app/iTerm2/Ghostty/VS Code terminal windows.

### Key Anchors

- Known good per user: `3fa85e4bcb8189636fa044832f2558beb85627c7`
- Current main latest at handoff: `5bf130c fix(ios): clear terminal cache on entry`
- Rescue worktree: `/Users/xin/auto-skills/CtriXin-repo/mms-remote-rescue-3fa`
- Rescue branch: `rescue/terminal-3fa-clean`

### Failed / Risky Areas

- Synthetic iOS pane targets (`mms-N:0.0`) became stale and mismatched real tmux `%pane_id`.
- iOS retained stale terminal tabs/errors across rebuilds.
- Bridge logs sometimes showed successful `terminal/list` but no `attach/snapshot` after user click.
- Runtime had mixed launchd Bridge, foreground local Bridge, and tmux sessions, making verification noisy.

### Validation Already Run

- Node terminal tests passed on main after rescue attempts.
- Swift parse passed on main after rescue attempts.
- Generic iOS build passed for build `118`.
- Rescue worktree based on `3fa85e4` + compile fix passed Node terminal tests and generic iOS build for build `119`.

### Recommended Verification After Merge

```bash
cd /Users/xin/auto-skills/CtriXin-repo/mms-remote
git status -sb
git log --oneline -8

# stop all old runtime
HOME=/Users/xin MMS_REMOTE_DEVICE_STATE_DIR=/Users/xin/.mms-remote node ./mms-remote-bridge/bin/mms-remote.js stop --json || true
pkill -f '/mms-remote-bridge/bin/mms-remote.js' || true
pkill -f 'run-local-mms-remote.sh' || true
pkill -f 'relay/server.js' || true
tmux kill-server || true

# one clean pane
tmux new-session -d -s mms-clean -c /Users/xin/auto-skills/CtriXin-repo/mms-remote

# start intended bridge only
MMS_REMOTE_RELAY=wss://<private-relay>/relay HOME=/Users/xin MMS_REMOTE_DEVICE_STATE_DIR=/Users/xin/.mms-remote node ./mms-remote-bridge/bin/mms-remote.js restart --json
HOME=/Users/xin MMS_REMOTE_DEVICE_STATE_DIR=/Users/xin/.mms-remote node ./mms-remote-bridge/bin/mms-remote.js status --json
```

Expected first acceptance: iOS Terminal shows exactly `mms-clean:0.0`; clicking it loads content; sending `pwd` updates the same tmux pane.

## 2026-05-15 10:16 -0400 — Swift Tab / SwiftTerm Stream Handoff

Status: Phase 6 code/build gate complete, phone smoke pending.

Key boundary:
- New work lives in the bottom `Swift` tab.
- Existing `Terminal` tab remains the stable CLI/snapshot fallback; do not enable SwiftTerm there by default.

Touched feature files:
- `CodexMobile/CodexMobile/ContentView.swift`
- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`
- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`
- `CodexMobile/CodexMobile/Models/TerminalModels.swift`
- `CodexMobile/CodexMobile/Services/CodexService.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Terminal.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Incoming.swift`
- `CodexMobile/CodexMobile/Services/LocalizationManager.swift`
- `mms-remote-bridge/src/terminal-protocol.js`
- `mms-remote-bridge/src/terminal-stream-hub.js`
- `mms-remote-bridge/src/tmux-control-adapter.js`
- `mms-remote-bridge/src/terminal-hub.js`
- `mms-remote-bridge/src/tmux-adapter.js`

Validation now passed:
- Node targeted suite: 41/41 pass.
- Generic iOS device build: `BUILD SUCCEEDED`.
- Local tmux stream smoke: `terminal/stream/start` emitted output and bytes input produced `stream-live`.

Next verification:
- Install on phone and run the Phase 6 manual matrix from `.ai/plan/swiftterm-phase6-checklist.md`: zsh/bash, vim, less, top, git add -p, claude/codex TUI, REPLs, CJK/emoji, resize/orientation, background/foreground.

## 2026-05-15 10:20 -0400 — Device Install Done / Manual Smoke Blocked

- Installed and launched build `23` on `song的iPhone` (`009568BB-3B27-5C91-A94D-34B683F6BCD5`) using `HOME=/Users/xin ./CodexMobile/scripts/deploy-ios-device.sh --device 009568BB-3B27-5C91-A94D-34B683F6BCD5`.
- The script auto-bumped `CURRENT_PROJECT_VERSION` from `22` to `23`.
- Build/sign/install/launch succeeded.
- Remaining Phase 6 blocker: manual visual verification on the physical phone. Run `.ai/plan/swiftterm-phase6-checklist.md` and record failures before changing renderer logic.

## 2026-05-16 02:51 -0400 — Stable Terminal Baseline Checkpoint

- agent: Codex
- task_id: terminal-health-hardening-baseline
- status: user-confirmed stable baseline before Terminal health hardening/refactor
- version: 1.7.17 build 53
- boundary: keep Terminal/CLI behavior and legacy fallback intact; avoid large UI changes; split only after health hardening; no Xcode tests unless requested
- next_action: apply P0 low-risk Terminal hardening: shared pane matching, shared text sanitization, cheaper stream seq/buffer handling, reconnect guardrails, then build/deploy to song的iPhone

## 2026-05-16 03:00 -0400 — Terminal Health Hardening P0

- agent: Codex
- task_id: terminal-health-hardening-p0
- status: completed; installed version 1.7.18 build 54 on song的iPhone; launch blocked by locked device
- baseline: 1.7.17 build 53 recorded as stable checkpoint before changes
- changed: shared pane matching via ManagedTerminalPane.matches(target:), shared terminal text cleanup utility, stream seq dedupe via lastSeq, cheaper stream buffer trim, SwiftTerm stream error/exit reconnect guard
- validation: Node terminal tests 27/27 pass; iOS generic Debug build succeeded; iOS device Debug build succeeded; Xcode tests not run by rule
- deploy: installed on song的iPhone / 00008150-0008781C36D9401C; did not install to iPhone 15 ProX雨; launch denied because device locked
- next_action: manual phone smoke after unlock, then split SwiftTerminalHubView only in small file-by-file steps

## 2026-05-16 03:24 -0400 — SwiftTerm Live Input Dedupe Relaxed

- agent: Codex
- CLI: codex
- model: GPT-5
- task_id: ios-swiftterm-live-input-dedupe
- status: version `1.7.19` build `55` built, installed, and launched on `song的iPhone`
- next_action: user verifies SwiftTerm experimental command echo; keep stable renderer as trusted default

### TL;DR

SwiftTerm live keyboard bytes were being de-duped too broadly. Repeated printable bytes (`oo`, spaces, arrows via byte path, etc.) could be swallowed or make command echo look corrupted. This slice limits byte de-dupe to duplicate Enter/line-ending only.

### Changed Files

- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`
  - only suppress duplicate line-ending sends from SwiftTerm delegate.
- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`
  - only suppress duplicate line-ending byte input before forwarding to Bridge.
- `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`
  - bumped `MARKETING_VERSION = 1.7.19`, `CURRENT_PROJECT_VERSION = 55`.

### Validation

- Passed: targeted Node terminal tests `27/27`.
- Passed: generic iOS Debug build.
- Passed: device iOS Debug build for `00008150-0008781C36D9401C`.
- Passed: installed to devicectl device `009568BB-3B27-5C91-A94D-34B683F6BCD5` (`song的iPhone`).
- Passed: launched `com.mms.remote` on `song的iPhone`.
- Xcode tests not run per project rule.

## 2026-05-16T00:00:00-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=swift-terminal-refactor-safe-slice
- TL;DR: Stable baseline `1.7.21 build 57` is confirmed; starting a no-behavior-change SwiftTerminalHubView split.
- Next action: Extract Swift Terminal support types, bump to `1.7.22 build 58`, run Node terminal tests + iOS generic/device build, then install/launch on song device only.
- Scope / boundary: Preserve Terminal/CLI tab, stable renderer default, SwiftTerm experimental path, and legacy fallback.
- Device safety: install only to `009568BB-3B27-5C91-A94D-34B683F6BCD5` / xcode destination `00008150-0008781C36D9401C`.

## 2026-05-16T00:10:00-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=swift-terminal-refactor-safe-slice
- TL;DR: Split Swift Terminal support types out of `SwiftTerminalHubView.swift` into `SwiftTerminalTypes.swift`; no intended behavior change.
- Version/build: bumped CodexMobile to `1.7.22 build 58`.
- Validation: Node terminal suite passed `27/27`; iOS generic Debug build passed; iOS device Debug build passed.
- Device: installed on `song的iPhone` (`009568BB-3B27-5C91-A94D-34B683F6BCD5`); launch via `devicectl` was blocked because the device was locked.
- Scope / boundary: Terminal/CLI tab and legacy fallback were not touched.

## 2026-05-16T00:25:00-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=swift-terminal-stable-snapshot-split
- TL;DR: User confirmed `1.7.22 build 58` is fine; starting next no-behavior-change split.
- Next action: Extract `StableTerminalSnapshotTextView`, bump to `1.7.23 build 59`, run Node terminal tests + iOS generic/device build, install/launch on song device only.
- Scope / boundary: Preserve Terminal/CLI tab, stable renderer default, SwiftTerm experimental path, and legacy fallback.

## 2026-05-16T04:17:00-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=swift-terminal-stable-snapshot-split
- TL;DR: Completed no-behavior-change extraction of `StableTerminalSnapshotTextView`; installed and launched `1.7.23 build 59` on `song的iPhone`.
- Changed: `CodexMobile/CodexMobile/Views/Terminal/StableTerminalSnapshotTextView.swift` extracted from `SwiftTerminalHubView.swift`; current SwiftTerminalHubView is smaller without intended behavior change.
- Version/build: verified app bundle `CFBundleShortVersionString=1.7.23`, `CFBundleVersion=59`.
- Validation: Node terminal tests passed `27/27`; iOS generic Debug build passed; iOS device Debug build passed; Xcode tests not run by rule.
- Device: installed and launched only on `song的iPhone` (`009568BB-3B27-5C91-A94D-34B683F6BCD5` / xcode destination `00008150-0008781C36D9401C`).
- Smoke focus: Settings/About version, stable Terminal visibility, input/paste/Enter/Backspace/arrows/Ctrl-C, shortcut bar/pinned/chord/cheatsheet, tmux pane switch refresh, CLI fallback unchanged.

## 2026-05-16T04:20:00-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=swift-terminal-stable-snapshot-split-user-confirm
- TL;DR: User confirmed `1.7.23 build 59` is fine on device.
- Stable point: Terminal stable renderer, shortcuts/chord/cheatsheet, tmux pane refresh, and CLI fallback have no reported issue after install/launch.
- Next safe direction: continue only small no-behavior-change Terminal refactors or isolated polish; bump version/build for any iOS code change.

## 2026-05-16T04:30:00-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=swift-terminal-shortcut-view-split
- TL;DR: Completed no-behavior-change extraction of shortcut/key bar UI into `SwiftTerminalShortcutViews.swift`; installed `1.7.24 build 60` on `song的iPhone`; launch blocked because device locked.
- Changed: `SwiftTerminalKeyBarView`, `SwiftTerminalChordComposerPanel`, `SwiftTerminalShortcutEditorSheet`, and `SwiftTerminalPinnedShortcutPickerSheet` moved out of `SwiftTerminalHubView.swift`.
- Version/build: verified app bundle `CFBundleShortVersionString=1.7.24`, `CFBundleVersion=60`.
- Validation: Node terminal tests passed `27/27`; iOS generic Debug build passed; iOS device Debug build passed; Xcode tests not run by rule.
- Device: installed only on `song的iPhone` (`009568BB-3B27-5C91-A94D-34B683F6BCD5` / xcode destination `00008150-0008781C36D9401C`).
- Launch: `devicectl` launch failed with `Locked`; user can open manually after unlock.
- Smoke focus: version, stable Terminal visibility/input, shortcut bar expand/collapse, pinned picker reorder, chord panel send/resize, cheatsheet, tmux pane switch, CLI fallback unchanged.

## 2026-05-16T04:34:00-04:00 | agent=Codex | cli=codex | model=GPT-5 | task=bridge-connect-timeout-recovery
- TL;DR: User reported connect timeout; Bridge process was not running. Restarted macOS Bridge service with hosted relay config; status became `running` / `connected`; launched app on `song的iPhone`.
- Validation: `mms-remote.js status --json` showed launchd loaded, bridge pid present, connectionStatus `connected`. iOS launch via `devicectl` succeeded.
- Note: No iOS code change; no version bump needed.
