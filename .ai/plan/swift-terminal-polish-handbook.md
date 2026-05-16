# Swift Terminal Polish Handbook

- timestamp: 2026-05-15T21:20:00-04:00
- owner: Codex
- CLI: codex
- model: GPT-5
- task_id: swift-terminal-polish-v2
- status: handoff-ready
- next_action: 新 session 实现 compact chord UI、theme/style isolation、bottom Settings tab，然后 bump build、验证、安装。

## TL;DR

当前 Swift tab stable terminal 可用，最后一轮已加基础组合键能力，但 UI 占地大，只覆盖 symbols/common keys。下一轮做三件事：

1. 把组合键 UI 改成 compact sheet/popover，支持 `⌘/⌃/⌥/⇧ + 字母/数字/符号/Nav/Fn`。
2. 修 Swift tab 样式：避免黑底黑字，避免切 tab 把其他 tab 染黑；做局部 light/dark/system theme，不用全局 UIKit appearance hack。
3. 底部 tab 从 `Chats / Terminal / Swift` 扩成 `Chats / Terminal / Swift / Settings`。

## Baseline

- installed app: `1.7.4 build 40`
- device deploy: success, app launched
- Bridge runtime: restarted after JS change, iPhone reconnected
- Node validation: `node --test mms-remote-bridge/test/terminal-hub.test.js mms-remote-bridge/test/terminal-stream-hub.test.js` -> `19/19 pass`
- iOS validation: generic Debug build succeeded; device Debug build/install/launch succeeded
- Do not run Xcode tests unless user asks.

## Current Implementation State

Relevant files:

- `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`
  - Has `@AppStorage("swiftTerminal.chordMode")`.
  - Has inline `chordComposerBar` under expanded key bar.
  - Has `SwiftTerminalChordModifier` and `SwiftTerminalChordKey.commonKeys`.
  - Current common keys are mostly symbols/nav; no A-Z or 0-9 UI yet.
  - `ManagedTerminalKey.swiftTerminalKeyValue(from:)` already accepts compound modifiers and one-char suffixes, so `command-control-a`, `command-shift-1`, `control-option-=` are valid on iOS side.
- `mms-remote-bridge/src/tmux-adapter.js`
  - `normalizeCompoundTmuxKey()` maps multi-modifier keys.
  - `command`/`cmd` maps to tmux `M` because terminal/tmux has no real Command modifier.
  - Examples: `command-control-=` -> `C-M-=`, `control-option-delete` -> `C-M-DC`.
- `mms-remote-bridge/test/terminal-hub.test.js`
  - Existing Mac-style shortcut test includes compound examples.
- `CodexMobile/CodexMobile/Services/LocalizationManager.swift`
  - Has chord strings in zh/en.
- `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`
  - Current app target: `MARKETING_VERSION = 1.7.4`, `CURRENT_PROJECT_VERSION = 40`.

## User Requests For Next Slice

### 1. Compact Combination Key UI

Problem:

- Inline chord panel takes too much vertical space.
- It does not expose letters/digits.

Recommended UX:

- Replace inline `chordComposerBar` with one compact button in key bar, e.g. `⌘K` / `组合键`.
- Tapping opens a bottom sheet or popover, not inline expanded content.
- Sheet structure:
  - top preview row: selected modifiers + selected key preview, e.g. `⌘⌃=` / `command-control-=`
  - modifier chips: `⌘`, `⌃`, `⌥`, `⇧`, multi-select, sticky while sheet open
  - segmented pages: `ABC`, `123`, `符号`, `Nav`, `Fn`
  - key grid changes by page
  - optional close button; sending a key may keep sheet open for repeated shortcuts
- Add keys:
  - letters: `A-Z`, values `a-z`, `textValue` lowercase when no modifier
  - digits: `0-9`, values `0-9`, `textValue` digit when no modifier
  - symbols: current symbols plus `+`, `_`, `:`, `'`, `"`, `<`, `>`, `?`, `~`
  - nav: arrows, home/end, page up/down, tab, shift-tab, esc, enter, backspace, delete
  - fn: `F1-F12`
- Display preview compactly:
  - modifier glyphs for UI: `⌘⌃⌥⇧`
  - normalized key string for debugging in small secondary text

Implementation hints:

- Add enum `SwiftTerminalChordKeyPage: String, CaseIterable` with localized title.
- Replace `SwiftTerminalChordKey.commonKeys` with static groups, e.g. `letters`, `digits`, `symbols`, `navigation`, `functionKeys`.
- Keep no-modifier behavior: if `textValue != nil`, call `sendText(textValue)`; otherwise `sendKeyValue(value)`.
- With modifiers: `sendKeyValue((prefixes + [key.value]).joined(separator: "-"))`.
- Do not over-engineer hardware-key capture yet; this is tap-composed virtual keyboard.

Bridge/key compatibility:

- iOS validator currently allows one-character suffixes, so letters/digits/symbols pass.
- Bridge currently allows `suffix.length === 1`, so letters/digits/symbols pass.
- Add tests for:
  - `command-control-a` -> `C-M-a`
  - `command-shift-1` -> `M-S-1`
  - `control-option-9` -> `C-M-9`

Risk:

- tmux support for some `C-M-symbol` combos can vary by terminal/app. If a combo does not work manually, fallback path is sending escape/control byte sequences for specific common chords, but do not add broad byte hacks unless proven.

### 2. Theme / Style Fix

Problems user saw:

- Swift tab black background; input area and font-size stepper can show black text on black.
- Switching tabs can make other tabs look black.
- Existing Terminal tab is white and feels OK.

Recommended approach:

- Do not use global `UINavigationBar.appearance`, `UITabBar.appearance`, or broad `.preferredColorScheme` inside Swift tab; those can bleed across tabs.
- Add local Swift terminal theme tokens instead:
  - `shellBackground`
  - `panelBackground`
  - `terminalSurface`
  - `primaryText`
  - `secondaryText`
  - `buttonBackground`
  - `accent`
- Add `@AppStorage("swiftTerminal.themeMode")` with `system`, `light`, `dark`.
- Default should be `system` or `light shell + dark terminal surface`. Given user says Terminal tab white is good, safest default: light shell controls, optional dark terminal canvas/card.
- Ensure all controls explicitly set readable text:
  - `TextField`: foreground/tint/background
  - `Stepper` label and buttons area: foreground/tint
  - `Toggle`: foreground/tint
  - shortcut buttons: selected/unselected contrast
  - key bar/settings row: no default black-on-dark labels
- Keep terminal output readable; stable renderer can remain Ghostty-like dark canvas if controls around it are light.
- For tab bleed:
  - Prefer local `.background(theme.shellBackground)` without `.ignoresSafeArea()` over whole screen dark if not needed.
  - If tab bar needs color, set it in `ContentView.swift` once with semantic `Color(.systemBackground)` / `Color(.secondarySystemBackground)`, not from Swift tab.

Validation checklist:

- Swift tab light mode: no black text on black.
- Swift tab dark mode: no black text on black.
- Switch `Chats -> Terminal -> Swift -> Settings -> Chats`: other tabs do not inherit Swift black background.
- Keyboard open/close still allows scroll.

### 3. Bottom Settings Tab

Request:

- Bottom tabs currently `Chats / Terminal / Swift`.
- Add `Settings` button/tab to bottom.

Recommended implementation:

- Edit `CodexMobile/CodexMobile/ContentView.swift`.
- Add fourth `Tab` / `tabItem` using existing `SettingsView`.
- Use localized key `tab.settings` in zh-Hans/en via `LocalizationManager.swift`.
- SF Symbol: `gearshape` or `gearshape.fill`.
- Keep existing settings entry points for now; do not delete sidebar/floating settings until user confirms.
- Check if tab enum exists; add `.settings` case if needed.

Risk:

- There may be existing sidebar settings button and onboarding/settings sheets; avoid moving logic. Just add route/tab.

### 4. Build Version Rule

User explicitly wants build increased every time so they know change installed/effective.

Current:

- `MARKETING_VERSION = 1.7.4`
- `CURRENT_PROJECT_VERSION = 40`

Next iOS code slice should end at:

- `MARKETING_VERSION = 1.7.5`
- `CURRENT_PROJECT_VERSION = 41`

If using `CodexMobile/scripts/deploy-ios-device.sh`, it auto-bumps build by +1. So manually set marketing to `1.7.5`, start from build `40`, let deploy script bump to `41`.

## Validation Commands

From repo root:

```bash
node --test mms-remote-bridge/test/terminal-hub.test.js mms-remote-bridge/test/terminal-stream-hub.test.js
HOME=/Users/xin xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS' build
HOME=/Users/xin DERIVED_DATA=/tmp/mms-remote-ios-device ./CodexMobile/scripts/deploy-ios-device.sh --device 009568BB-3B27-5C91-A94D-34B683F6BCD5
```

After Bridge JS changes:

```bash
tmux send-keys -t mms-remote-swiftterm-bridge:0.0 C-c 2>/dev/null || true
sleep 2
if tmux has-session -t mms-remote-swiftterm-bridge 2>/dev/null; then tmux kill-session -t mms-remote-swiftterm-bridge; fi
tmux new-session -d -s mms-remote-swiftterm-bridge -c /Users/xin/auto-skills/CtriXin-repo/mms-remote './run-local-mms-remote.sh'
```

Do not log or paste live pairing codes/session IDs in handoff.

## Review Checklist For Codex/Reviewer

- Existing `Terminal/CLI` tab behavior untouched.
- `Swift` tab stable renderer still default.
- Chord UI is compact; no large always-visible grid.
- Letters/digits/symbols/nav/fn supported.
- Custom JSON still supports `command-control-=` style values.
- Light/dark/system style has no black-on-black controls.
- Switching tabs does not leak dark styling globally.
- Bottom Settings tab appears and opens existing settings.
- Version/build visibly changed.
- Node tests + iOS build + device install pass.

## Suggested New Session Prompt

```text
继续 mms-remote：读取 .ai/plan/swift-terminal-polish-handbook.md。
任务：实现 compact combination key UI（支持修饰键+字母/数字/符号/Nav/Fn）、修 Swift tab light/dark/style bleed、底部加 Settings tab。每次 iOS 改动 bump version/build；这轮目标 1.7.5 build 41。不要跑 Xcode tests；跑 Node terminal tests、iOS generic build、device deploy。保持 Terminal/CLI tab 不受影响。
```
