# Current Handoff — Terminal SwiftTerm Stabilization

- timestamp: 2026-05-16T04:30:00-04:00
- owner: Codex
- CLI: codex
- model: GPT-5
- task_id: swift-terminal-shortcut-view-split
- status: installed `1.7.24 build 60` on `song的iPhone`; launch blocked because device locked; user smoke pending

## Stable Checkpoint

- User confirmed `1.7.23 build 59` looked fine before this slice.
- Stable renderer remains trusted/default.
- SwiftTerm live renderer remains experimental.
- Keep legacy/fallback Terminal path until explicit approval to delete.
- Do not run Xcode tests unless explicitly requested.

## Completed Slice

- Low-risk refactor only: split shortcut/key bar UI into `SwiftTerminalShortcutViews.swift`.
- No intended behavior change to Terminal/CLI tab, stable renderer, shortcuts, chord panel, pinned picker, or SwiftTerm stream path.
- `SwiftTerminalHubView.swift` reduced from 2109 lines to 1857 lines.
- Version/build: `1.7.24 build 60`.

## Validation Done

1. Node terminal tests: passed `27/27`.
2. iOS generic Debug build: passed.
3. iOS device Debug build for `song的iPhone`: passed.
4. App Info.plist verified: `CFBundleShortVersionString=1.7.24`, `CFBundleVersion=60`.
5. Installed on `song的iPhone` only.
6. Launch blocked: iPhone locked (`FBSOpenApplicationRequestDenied`, `Locked`).
7. Xcode tests not run per project rule.

## Device Safety

- `devicectl` song device id: `009568BB-3B27-5C91-A94D-34B683F6BCD5`.
- `xcodebuild` destination id: `00008150-0008781C36D9401C`.
- Do not install to `iPhone 15 ProX雨`.

## User Smoke Focus

- Settings/About shows `1.7.24 build 60`.
- Terminal stable renderer content visible; no blank screen or double display.
- Input, paste, Enter, Backspace, arrows, Ctrl-C.
- Shortcut bar expanded/collapsed behavior unchanged.
- Pinned keys picker opens, toggles, and drag-reorders pinned keys.
- Chord panel opens, closes, resizes, and sends modifier+key combos.
- Cheatsheet sheet opens/closes.
- tmux pane previous/next switch refreshes.
- CLI/legacy fallback unchanged.
