# Current Handoff — MMS Remote Terminal

- timestamp: 2026-05-15 16:34 +0800
- owner: Codex
- CLI: codex
- model: GPT-5
- task_id: ios-terminal-running-branch
- status: running branch verified by user; local terminal hardening pending merge
- next_action: merge `codex/ios-remote-22e6243` as the code truth, then run clean bridge/iPhone acceptance before stacking new planner work

## Goal

Phone Terminal controls Mac tmux-managed terminal panes while Codex Chat remains a separate app entry point.

## Current Truth

- active worktree: `/Users/xin/auto-skills/CtriXin-repo/mms-remote-ios-22e6243`
- branch: `codex/ios-remote-22e6243`
- base: `22e624367783234245d0b0724c34212f79722e84`
- user-tested status: real phone no longer stuck on `Terminal Error`
- known-good anchor from previous rescue: `3fa85e4bcb8189636fa044832f2558beb85627c7`

## Current Changes

- iOS Terminal background list polling no longer surfaces modal `Terminal Error` alerts; manual refresh still reports errors.
- Ghostty visible open now uses AppleScript `new tab` / `new window` instead of `open -n`, avoiding duplicate restored tab layouts.
- iTerm2 visible open now prefers a new tab in the current window, falling back to a new window.
- Terminal quick keys include Enter, Backspace, Ctrl-C/D/Z/A/E, Tab, Esc, Home/End, PgUp/PgDn, and arrows.
- Current SwiftUI terminal snapshot viewer is a stopgap dark terminal surface with horizontal+vertical scrolling and no automatic line wrapping.
- Full iTerm/Ghostty-like rendering still requires a real terminal renderer such as SwiftTerm or xterm.js.

## Validation

- `node --test test/terminal-visible-launcher.test.js test/terminal-hub.test.js test/mms-remote-cli.test.js` passed: 32/32.
- `xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'platform=iOS Simulator,id=4F06CB43-A708-44E5-8418-ABF70A2D4887' -derivedDataPath .build/DerivedData build` succeeded.
- Full `npm test` earlier had 307/308 passing; only `bridge-desktop-ipc-integration.test.js` timed out, not adjacent to terminal launcher changes.

## Boundaries

- Do not promise automatic capture of arbitrary existing Terminal.app/iTerm2/Ghostty panes unless they join tmux.
- Keep local-first Bridge/QR/daemon workflow.
- Do not run Xcode tests unless user explicitly asks.
- Before further terminal-renderer work, decide SwiftTerm native renderer vs WKWebView+xterm.js.
