# Next Agent Prompt — Terminal-First MMS Remote

## Latest Stable Slice

- Latest user-confirmed stable build: `1.7.23 build 59` on `song的iPhone`.
- Latest installed build: `1.7.24 build 60`; phone launch blocked because device locked, so user smoke pending.
- Latest slice is low-risk refactor only: `SwiftTerminalShortcutViews.swift` extracted shortcut/key bar UI from `SwiftTerminalHubView.swift`.
- Validation passed: Node terminal tests `27/27`, iOS generic Debug build, iOS device Debug build, install on `song的iPhone`.
- Xcode tests not run by rule.

## Current Truth

- `main` 是当前真相，但工作区有未提交改动；不要重置或覆盖。
- 用户真机确认：之前一直弹 `Terminal Error` 的问题已消失。
- 当前产品决策：MMS Remote 采用底部 `Tab Bar`，分成 `Chats` 和 `Terminal` 两个入口。
- `Chats` 是 lightweight Codex companion。
- `Terminal` 是 first-class mobile terminal，控制 Mac tmux-managed panes。

## First Read

1. `.ai/plan/current.md`
2. `.ai/plan/handoff.md`
3. `.ai/plan/packet.json`
4. `CodexMobile/CodexMobile/ContentView.swift`
5. `CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift`
6. `CodexMobile/CodexMobile/Views/Terminal/SwiftTermTerminalView.swift`
7. `CodexMobile/CodexMobile/Services/CodexService+Terminal.swift`
8. `mms-remote-bridge/src/terminal-hub.js`
9. `mms-remote-bridge/src/tmux-adapter.js`

## Product Rules

- Keep Bottom Tab Bar. Do not move Terminal back into Chat toolbar.
- Do not make Sidebar segmented switch unless user explicitly reverses decision.
- Do not build a Dashboard launcher unless product strategy changes.
- Do not copy full Codex App. Official open-source reference is `openai/codex` / CLI / SDK / App Server / Skills, not full App UI.
- Terminal UX should reference iTerm/Ghostty quality: spacing, keyboard behavior, readable ANSI, stable full-screen app rendering.

## Localization Rules

- Treat localization as part of every UI change, not a cleanup task.
- Every new visible iOS string needs both `zh-Hans` and `en` entries.
- Keep technical terms in English: `Codex`, `Terminal`, `tmux`, `Bridge`, `iTerm2`, `Ghostty`, `SwiftTerm`, `QR`.
- Use the shared localization layer only: `LocalizationManager.shared.localized(key)` or verified localized SwiftUI wrappers.
- Do not invent per-view APIs such as `navigationTitle(localized:)` / `Label(localized:)`; SwiftUI overload ambiguity can break device builds.
- Include navigation titles, alerts, buttons, placeholders, empty states, and accessibility text.
- Exempt only developer logs, comments, tests, and protocol constants.

## Current Work In Progress

- `ContentView.swift` now has `Chats` and `Terminal` tabs.
- `TerminalHubView.onClose` is optional; independent Terminal tab hides old `Chats` button.
- Other current dirty changes include SwiftTerm renderer attempt, ANSI snapshot params, terminal bytes input, resize, copy/paste/modifier requests, tmux tests.
- Important rescue: SwiftTerm snapshot renderer caused phone lag/no cursor/no visible echo. It is now behind `terminal.experimentalSwiftTermRenderer` and defaults off. Do not turn it back on by default until output is stream/control-mode based.
- Latest foundation patch hard-disables the experimental SwiftTerm snapshot path, removes horizontal Terminal UI scroll, wraps output, resizes tmux to the phone viewport, strips unsupported PUA glyphs, and sends input edits directly to tmux.

## Must Fix Next

1. Phone-verify stable fallback first:
   - no horizontal terminal output scroll
   - no clipped/centered terminal viewport
   - no missing-glyph boxes in common prompts
   - typing appears through tmux echo
   - Enter
   - Tab
   - paste
   - Ctrl-C
   - Ctrl-D
2. Keep stable snapshot + direct input as default until SwiftTerm has real stream/control-mode semantics.
3. Make SwiftTerm compile and run as experimental terminal canvas only.
4. Verify input execution:
   - tap focus
   - soft keyboard
   - hardware keyboard
   - Enter
   - paste
   - Ctrl-C
   - Ctrl-D
5. Replace current basic quick keys with modifier-latch keyboard:
   - `Ctrl`
   - `Alt/Meta`
   - `Esc`
   - `Fn`
   - arrows
   - custom key bar presets
6. Add Terminal settings:
   - preferred Mac visible terminal app: `auto`, Ghostty, iTerm2, Terminal.app
   - font size
   - theme
   - key bar layout
7. Move protocol toward stream/delta or viewport-aware ANSI snapshot with resize negotiation.
8. Split `TerminalHubView` later:
   - session strip
   - terminal canvas
   - key bar
   - create sheet
   - settings

## Wrong Directions

- Terminal as a Chat toolbar feature.
- More random shortcut buttons as the main fix.
- SwiftUI `Text` snapshot viewer as final renderer.
- Feeding whole `tmux capture-pane` snapshots into SwiftTerm as the default renderer.
- Full Codex App clone.
- Promise to capture arbitrary non-tmux Terminal.app/iTerm2/Ghostty windows.

## Validation

Do not run Xcode tests unless user explicitly asks. Build is okay if needed.

Current validation already passed:

- Node terminal tests: 34/34.
- iOS Debug simulator build: `BUILD SUCCEEDED`.
- Xcode tests: not run.

```bash
cd /Users/xin/auto-skills/CtriXin-repo/mms-remote

node --test \
  mms-remote-bridge/test/terminal-hub.test.js \
  mms-remote-bridge/test/terminal-visible-launcher.test.js \
  mms-remote-bridge/test/mms-remote-cli.test.js

xcodebuild \
  -project CodexMobile/CodexMobile.xcodeproj \
  -scheme CodexMobile \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/DerivedData \
  build CODE_SIGNING_ALLOWED=NO
```

## Real Phone Acceptance

- App opens with bottom `Chats` / `Terminal` tabs.
- Terminal tab opens directly to terminal experience; no old `Chats` return button.
- Chat no longer has Terminal toolbar shortcut.
- Terminal can create/list/select tmux pane.
- Tap terminal, type `pwd`, press Enter, output updates on same pane.
- Claude/Codex TUI layout no longer shows severe clipping/drift after SwiftTerm work lands.
