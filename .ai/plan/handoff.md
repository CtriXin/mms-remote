# Handoff Log

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
MMS_REMOTE_RELAY=wss://remote.clawopen.online/relay HOME=/Users/xin MMS_REMOTE_DEVICE_STATE_DIR=/Users/xin/.mms-remote node ./mms-remote-bridge/bin/mms-remote.js restart --json
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
