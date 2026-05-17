# MMS Remote Project Handoff — 2026-05-16

- timestamp: 2026-05-16T05:50:00-04:00
- owner: Codex
- CLI: codex
- model: GPT-5
- task_id: mms-remote-handoff-20260516
- status: handoff-ready after `1.7.26 build 62`
- current_commit: `f676d48 feat(ios): add sidebar multi-select actions`
- latest_installed_device: `song的iPhone`
- next_action: keep current stable build as baseline, then continue with small validated slices.

## 0. TL;DR For Any Fresh Agent

This repo is now a local-first MMS Remote / Codex companion with two main product surfaces:

1. `Chats`: mobile companion for local Codex sessions.
2. `Terminal`: first-class mobile terminal for Mac `tmux` panes, with stable renderer as the safe default and SwiftTerm live renderer still experimental.

Latest stable point:

- iOS app: `1.7.26 build 62`.
- Commit: `f676d48 feat(ios): add sidebar multi-select actions`.
- Installed to `song的iPhone`.
- Node tests passed with real host env: `HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test` -> `325/325`.
- iOS generic Debug build passed.
- Signed device build/install passed.
- Xcode tests were not run by project rule.

Do not start by redesigning. First read this file, `.ai/plan/current.md`, `.ai/plan/handoff.md`, and `Docs/terminal_health_check.md`, then continue from the next-action section.

## 1. Hard Rules / Safety

- Always answer the user in Chinese-simplified; keep technical terms in English.
- Do not run Xcode tests unless the user explicitly asks.
- Every iOS code change must bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`; docs-only does not need a bump.
- Install only to `song的iPhone` unless user changes the target.
- Known device IDs:
  - `devicectl` device id: `009568BB-3B27-5C91-A94D-34B683F6BCD5`
  - `xcodebuild` destination id: `00008150-0008781C36D9401C`
- Do not manage/restart Bridge unless necessary; user prefers starting Bridge themselves to keep QR control.
- Use `HOME=/Users/xin` for signed iOS builds.
- Use `HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test` for full Node tests; isolated HOME currently fails generated-image path assertions.
- Do not delete legacy Terminal fallback without explicit user approval.
- Do not reset/revert dirty files you did not create. Current worktree has `.ai/exec/`, `.ai/plan/p184-*`, `.omc/`, `tmp/` context from other work.

## 2. Read Order For Fresh Agents

1. `AGENTS.md`
2. `.ai/plan/mms-remote-project-handoff-20260516.md`
3. `.ai/plan/current.md`
4. `.ai/plan/handoff.md`
5. `.ai/plan/packet.json`
6. `Docs/terminal_health_check.md`
7. `git log -n 8 --oneline`
8. Relevant source files for the active task only.

Important source refs:

- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`
- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalShortcutViews.swift`
- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalTypes.swift`
- `CodexMobile/CodexMobile/Views/Terminal/StableTerminalSnapshotTextView.swift`
- `CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift`
- `CodexMobile/CodexMobile/Views/Terminal/TerminalTextUtilities.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Terminal.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Sync.swift`
- `CodexMobile/CodexMobile/Views/SidebarView.swift`
- `mms-remote-bridge/src/terminal-stream-hub.js`
- `mms-remote-bridge/src/tmux-control-adapter.js`
- `mms-remote-bridge/src/tmux-adapter.js`

## 3. Product Direction Already Decided

### 3.1 Local-first runtime

- This repo should stay local-first.
- Prefer local Mac runtime, local Bridge, QR pairing, local daemon workflows.
- Do not reintroduce hosted-service assumptions, remote production domains, or cloud deployment runbooks.
- Do not log live relay `sessionId`, QR, or bearer-like pairing identifiers.

### 3.2 App structure

- Bottom navigation is the chosen direction.
- `Chats` and `Terminal` are sibling product surfaces.
- `Terminal` must not be moved back into a Chat toolbar.
- Settings exists as an app-level tab/surface and should host global theme and Terminal/Codex-specific preferences.
- Swift/SwiftTerm terminology in UI was moved toward `Terminal`; keep user-facing naming simple.

### 3.3 Renderer strategy

- Stable snapshot renderer is trusted/default.
- SwiftTerm live renderer is experimental and must remain behind settings/fallback until proven stable.
- Legacy fallback Terminal path remains as a safety valve; delete only after explicit user approval and a safe replacement window.

## 4. What We Already Built / Changed

### 4.1 Terminal foundation rescue

Earlier Terminal UI had horizontal drift, clipping, missing glyph boxes, unstable input, and SwiftTerm snapshot lag. The foundation fixes:

- Disabled bad SwiftTerm snapshot-as-default path.
- Restored stable text snapshot renderer as default.
- Removed horizontal terminal output scroll.
- Anchored terminal output top-left and made wrapping predictable.
- Resized tmux viewport to phone dimensions.
- Sent edits/input directly to tmux instead of replaying full command line.
- Stripped unsupported private-use prompt glyphs when rendered by iOS fonts.
- Kept experimental SwiftTerm path gated.

Important files:

- `CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift`
- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Terminal.swift`
- `mms-remote-bridge/src/terminal-hub.js`
- `mms-remote-bridge/src/tmux-adapter.js`

### 4.2 Terminal product split

- Added bottom `Chats` / `Terminal` product split.
- `Terminal` is no longer a hidden toolbar feature under Chat.
- Terminal initializes lazily to avoid startup crash when opening into Chat.
- Terminal tab can list/select/create tmux panes.
- Stable renderer remains usable even if SwiftTerm path regresses.

Important files:

- `CodexMobile/CodexMobile/ContentView.swift`
- `CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift`
- `CodexMobile/CodexMobile/Views/SettingsView.swift`

### 4.3 tmux stream transport

Implemented bridge/iOS stream transport to move beyond repeated full snapshots:

- Added terminal stream protocol objects.
- Added `terminal-stream-hub.js`.
- Added `tmux-control-adapter.js`.
- Added stream start/stop/attach/replay handling.
- Buffered live output around replay boundaries to avoid lost initial output.
- Added `stopAll()` cleanup on tab switch, app background, disconnect, and Bridge shutdown.
- Added tests for protocol, stream hub, and tmux control adapter.

Important files:

- `mms-remote-bridge/src/terminal-protocol.js`
- `mms-remote-bridge/src/terminal-stream-hub.js`
- `mms-remote-bridge/src/tmux-control-adapter.js`
- `mms-remote-bridge/test/terminal-protocol.test.js`
- `mms-remote-bridge/test/terminal-stream-hub.test.js`
- `mms-remote-bridge/test/tmux-control-adapter.test.js`
- `CodexMobile/CodexMobile/Models/TerminalModels.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Terminal.swift`

### 4.4 Swift Terminal UI polish

Implemented and iterated the compact shortcut/chord work:

- Added compact combination-key UI for modifier + key composition.
- Supported modifiers and key groups: letters, digits, symbols, navigation, function keys.
- Added pinned/custom quick keys with reorderable display.
- Added keyboard conflict mitigations so shortcuts/chord panel do not fight the iOS keyboard as much.
- Added fixed-height/resizable chord area with scroll so terminal output remains visible.
- Changed unclear shortcut labels toward Mac-keyboard-like labels (`ESC`, symbols, abbreviations).
- Changed page up/down concept toward more useful pane/tab switching behavior where appropriate.
- Split shortcut/key bar code into `SwiftTerminalShortcutViews.swift` to reduce `SwiftTerminalHubView.swift` blast radius.
- Added cheatsheet surface and kept it as a support feature.

Important files:

- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`
- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalShortcutViews.swift`
- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalTypes.swift`
- `CodexMobile/CodexMobile/Services/LocalizationManager.swift`
- `mms-remote-bridge/test/terminal-hub.test.js`

### 4.5 Theme, branding, settings, font

- Added app-level Settings surface/tab direction.
- Moved theme out of Terminal-specific inline UI and toward app Settings.
- Added light/dark/system adaptation work; avoid global UIKit appearance bleed from Terminal tab.
- Added/used Hack Nerd Font assets for Terminal display.
- Updated global logo/icon assets to user-provided 3D-style logo.
- Renamed user-facing chat/product copy toward `Codex` where appropriate.
- Settings now needs clearer separation between Terminal settings and Codex settings; first cleanup exists but structure still needs refinement.

Important files:

- `CodexMobile/CodexMobile/Views/SettingsView.swift`
- `CodexMobile/CodexMobile/Models/AppFont.swift`
- `CodexMobile/CodexMobile/Models/TerminalPreferences.swift`
- `CodexMobile/CodexMobile/Fonts/`
- `CodexMobile/CodexMobile/Assets.xcassets/AppLogo.imageset/`
- `CodexMobile/MMSRemote.icon/Assets/`
- `CodexMobile/CodexMobile/Services/LocalizationManager.swift`

### 4.6 Chat / Codex UI polish

- Applied broader Codex branding across Chat UI.
- Polished many Turn view surfaces, badges, sheets, and labels.
- Markdown rendering for Codex replies was reported as a visual issue and received UI polish in the branding/Codex pass; still watch complex Markdown/code blocks during smoke testing.
- Kept timeline guardrails: item-scoped assistant rows, late reasoning deltas merge into existing rows, Stop fallback via `thread/read` if `turnId` is missing.

Important files:

- `CodexMobile/CodexMobile/Views/Turn/TurnMessageComponents.swift`
- `CodexMobile/CodexMobile/Views/Turn/TurnTimelineView.swift`
- `CodexMobile/CodexMobile/Views/Turn/TurnView.swift`
- `CodexMobile/CodexMobile/Services/CodexService+History.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Sync.swift`

### 4.7 Sidebar archive/delete and multi-select

Latest feature slice:

- Added archived chats view cleanup.
- Added bulk archived chat local removal.
- Added sidebar selection mode: right-side `选择/完成`, row checkmarks, bottom bulk actions.
- Bulk `归档` applies only to live chats.
- Bulk `删除` removes local phone copies only; it does not delete Mac/Codex source data.
- Existing single-row actions remain.

Important files:

- `CodexMobile/CodexMobile/Views/SidebarView.swift`
- `CodexMobile/CodexMobile/Views/Sidebar/ArchivedChatsView.swift`
- `CodexMobile/CodexMobile/Views/Sidebar/SidebarHeaderView.swift`
- `CodexMobile/CodexMobile/Views/Sidebar/SidebarThreadListView.swift`
- `CodexMobile/CodexMobile/Views/Sidebar/SidebarThreadRowView.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Sync.swift`

## 5. Version / Commit Timeline

Known milestone chain:

| Commit / Build | Purpose | State |
|---|---|---|
| `aaa8953` | Cherry-pick mobile stability fixes, localization support, reconnect/history guards | landed |
| `9108baa` | Add tmux stream transport and Bridge/iOS stream protocol | landed |
| `b81bb4f` | Polish Terminal UI/settings, add SwiftTerminal split files, Hack Nerd Font, deploy script | landed |
| `cd561d6` | Branding/logo/Codex UI polish | landed |
| `1cc3cea` | Planning docs and guardrails | landed |
| `dae9397` | Bulk archived chat removal | landed |
| `f676d48` | Sidebar multi-select archive/delete | latest stable |

Build checkpoints from handoff history:

- `1.6.2 build 25`: stream cleanup and Phase 6 blocker fixes installed; launch was blocked by locked phone.
- `1.7.4 build 40`: compact chord/theme/settings handbook baseline.
- `1.7.23 build 59`: user-confirmed stable before shortcut view split.
- `1.7.24 build 60`: low-risk shortcut view split installed; launch blocked by locked phone.
- `1.7.26 build 62`: latest installed stable point after archive/delete and multi-select sidebar.

## 6. Current Validation Truth

Most recent known validation:

- `git diff --check`: passed before/after latest installed slice.
- Node full suite with real user env: `HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test` -> passed `325/325`.
- Node default isolated HOME has known generated-image path failures; do not treat that as product regression without checking env.
- iOS generic Debug build passed.
- iOS signed device build passed.
- Device install to `song的iPhone` passed.
- Auto launch may fail if phone is locked; install can still be valid.
- Xcode tests not run per rule.

Useful commands:

```bash
cd /Users/xin/auto-skills/CtriXin-repo/mms-remote
HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test
HOME=/Users/xin xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData-generic build
HOME=/Users/xin DERIVED_DATA=/tmp/mms-remote-ios-device ./CodexMobile/scripts/deploy-ios-device.sh --device 009568BB-3B27-5C91-A94D-34B683F6BCD5
```

Do not run Xcode tests unless user explicitly asks.

## 7. What The User Should Smoke Test Next

For `1.7.26 build 62`:

1. Settings/About shows `1.7.26 build 62`.
2. Sidebar selection mode:
   - Tap `选择`.
   - Select several visible chats.
   - `归档` moves live chats to archived state.
   - `删除` removes selected local/archived phone entries only.
   - `完成` exits selection and clears checkmarks.
3. Archived chats:
   - Single delete still works.
   - Bulk remove all archived still works.
   - Removing archived local entries does not delete Mac/Codex source sessions.
4. Terminal stable renderer:
   - Content visible after entering/switching tab.
   - No blank screen after theme change or initial process switch.
   - Claude/Codex TUI scroll behavior remains usable.
   - Input, paste, Enter, Backspace, arrows, Ctrl-C work.
5. Shortcut/chord UI:
   - Pinned keys display fully enough and reorder correctly.
   - Combination panel does not get buried under iOS keyboard.
   - Terminal display area remains visible while chord panel is open.
6. Chat/Codex:
   - Markdown reply rendering is readable, especially code blocks and lists.

## 8. Open Risks / Known Issues

### P0 / should address soon

- Fresh agents must not mistake legacy `TerminalHubView.swift` for the final direction; stable renderer is safe, but product direction is `SwiftTerminalHubView`/Terminal with fallback.
- `SwiftTerminalHubView.swift` is still too large. Avoid large risky edits; split by bounded slices.
- Stream reconnect is not fully automatic; if stream dies, user may still need refresh/re-enter.
- Some keyboard conflict behavior may depend on Chinese input method and iOS keyboard focus timing.
- User has not fully smoke-tested latest sidebar multi-select on phone after this handoff.

### P1 / health-check items

- Merge duplicate `paneMatches` logic into one `ManagedTerminalPane` extension.
- Extract shared terminal sanitization utilities where duplication remains.
- Replace `TerminalStreamMessage` O(n) dedupe/trim patterns with `lastSeq` and ring-buffer/efficient trim.
- Add pane activity indicator in pane selector.
- Add Chat -> Terminal quick action for running command in current cwd/pane.
- Improve agent pane smart selection using existing scoring hints.

### P2 / cleanup only with caution

- Delete `TerminalHubView.swift` and legacy toggle only after explicit user approval and a stable release window.
- Consider removing dead SwiftTerm snapshot branches inside legacy view after fallback deletion approval.
- Reorganize Settings into clear `Terminal` section and `Codex` section.

## 9. Non-goals / Avoid

- Do not clone full Codex App UI.
- Do not add remote hosting or production-domain assumptions.
- Do not add SSH direct-connect as a random feature; it changes threat model and project scope.
- Do not add terminal recording/replay or in-terminal search unless user asks; ROI is low vs current reliability work.
- Do not build multiple independent terminal tabs on phone unless a strong workflow emerges; tmux pane switching is enough for now.
- Do not broaden low-level key-byte hacks for every modifier combo unless a specific failing combo is proven.

## 10. Current Workspace Notes

- `main` currently points to `f676d48`.
- There are untracked/modified agent docs from other contexts:
  - `.ai/exec/`
  - `.ai/plan/p184-mmschat-*`
  - `.ai/plan/progress/`
  - `.omc/`
  - `tmp/`
- Treat those as context artifacts unless the active task explicitly targets them.
- This handoff task updates `.ai/plan/*` only.

## 11. Fresh Session Continue Prompt

Use this exact prompt when starting a new agent session:

```text
继续 /Users/xin/auto-skills/CtriXin-repo/mms-remote。

先读：
1. AGENTS.md
2. .ai/plan/mms-remote-project-handoff-20260516.md
3. .ai/plan/current.md
4. .ai/plan/handoff.md
5. Docs/terminal_health_check.md
6. git log -n 8 --oneline

当前稳定点：
- commit: f676d48 feat(ios): add sidebar multi-select actions
- iOS: 1.7.26 build 62
- 已安装到 song 的 iPhone
- Node full tests 需用 HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test，已通过 325/325
- iOS generic build、signed device build、device install 已通过
- 不要跑 Xcode tests

当前任务状态：项目级交接文档已刷新。下一步优先小步迭代：先等/收集用户对 1.7.26/62 的多选归档删除与 Terminal smoke 反馈；如继续开发，优先做 Docs/terminal_health_check.md 的低风险项：合并 paneMatches、抽 TerminalTextUtilities/ANSI renderer、优化 stream buffer/seq 去重、加 stream reconnect。不要删除 legacy Terminal fallback，除非用户明确同意。

约束：
- 中文简体回复，技术词 English
- 不要非必要管理 Bridge
- iOS code change 必须 bump version/build；docs-only 不用
- 安装只到 song 的 iPhone
- 不要动无关 dirty files
- 不要跑 Xcode tests
```
