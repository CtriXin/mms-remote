# Current Handoff — MMS Remote Terminal

- timestamp: 2026-05-15 16:47 +0800
- owner: Codex
- CLI: codex
- model: GPT-5
- task_id: ios-terminal-running-branch
- status: merged to `main`; branch-wins merge complete
- next_action: start next task from `main` and integrate SwiftTerm as the iOS Terminal renderer

## Goal

Phone Terminal controls Mac tmux-managed terminal panes while Codex Chat remains a separate app entry point.

## Current Truth

- active worktree: `/Users/xin/auto-skills/CtriXin-repo/mms-remote`
- branch: `main`
- merge commit: `98072a8 merge: adopt ios terminal running branch`
- merged running branch: `codex/ios-remote-22e6243`
- merged running commit: `b7196688f9c26c9ed23407d8fd19c00143a0255f`
- base: `22e624367783234245d0b0724c34212f79722e84`
- backup of old main before merge: `codex/backup-main-before-ios-terminal-merge-20260515`
- user-tested status: real phone no longer stuck on `Terminal Error`
- known-good anchor from previous rescue: `3fa85e4bcb8189636fa044832f2558beb85627c7`

## Current Changes

- iOS Terminal background list polling no longer surfaces modal `Terminal Error` alerts; manual refresh still reports errors.
- Ghostty visible open now uses AppleScript `new tab` / `new window` instead of `open -n`, avoiding duplicate restored tab layouts.
- iTerm2 visible open now prefers a new tab in the current window, falling back to a new window.
- Terminal quick keys include Enter, Backspace, Ctrl-C/D/Z/A/E, Tab, Esc, Home/End, PgUp/PgDn, and arrows.
- Current SwiftUI terminal snapshot viewer is a stopgap dark terminal surface with horizontal+vertical scrolling and no automatic line wrapping.
- Full iTerm/Ghostty-like rendering still requires a real terminal renderer such as SwiftTerm or xterm.js.

## Next Task

- Implement SwiftTerm as the iOS Terminal renderer.
- Goal: make phone Terminal look and behave like a real terminal, not a styled log view.
- Keep current SwiftUI viewer only as fallback/debug path until SwiftTerm is stable.
- Do not ship an ugly half-renderer as final UX.

## SwiftTerm Acceptance

- ANSI colors render.
- Box drawing, separators, progress bars, prompt lines, and wide CJK text do not drift or wrap incorrectly.
- Cursor movement, clear screen, and shell prompt editing work.
- `top`/`htop`/`less`/`vim` render acceptably or fail gracefully with clear limitations.
- Theme defaults to a polished dark terminal style; font uses existing bundled mono first, later optional Nerd Font.

## Todo / Not Now

- Add a Terminal setting for preferred Mac visible terminal app: `auto`, Ghostty, iTerm2, or Terminal.app.
- Show the same selector in create/open flows later if UX needs per-launch override.
- Default stays `auto` for now: Ghostty -> iTerm2 -> Terminal.app.
- Use installed-app detection only for availability/labels; do not block manual selection unless launch fails.

## Validation

- `node --test test/terminal-visible-launcher.test.js test/terminal-hub.test.js test/mms-remote-cli.test.js` passed: 32/32.
- `xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'platform=iOS Simulator,id=4F06CB43-A708-44E5-8418-ABF70A2D4887' -derivedDataPath .build/DerivedData build` succeeded.
- Full `npm test` earlier had 307/308 passing; only `bridge-desktop-ipc-integration.test.js` timed out, not adjacent to terminal launcher changes.

## Boundaries

- Do not promise automatic capture of arbitrary existing Terminal.app/iTerm2/Ghostty panes unless they join tmux.
- Keep local-first Bridge/QR/daemon workflow.
- Do not run Xcode tests unless user explicitly asks.
- Before further terminal-renderer work, decide SwiftTerm native renderer vs WKWebView+xterm.js.
