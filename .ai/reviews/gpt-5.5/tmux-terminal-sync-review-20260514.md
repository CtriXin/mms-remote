# tmux-terminal-sync Review - Tmux Terminal Sync & Multi-Backend

- Date: 2026-05-14
- Reviewer: gpt-5.5
- CLI: codex
- Started: 2026-05-14T11:08:00-04:00
- Completed: 2026-05-14T11:15:00-04:00
- Duration: 7m

## Overall Verdict
BLOCKED

## Blocking Findings
- BLOCK-1: Declared milestone is not present in the reviewed commit. `.ai/plan/review-packs/tmux-terminal-sync.json:6` claims tmux transport, relay multi-client support, and iOS terminal renderer, but `.ai/plan/review-packs/tmux-terminal-sync.json:48` lists only `LICENSE`, and `git show --stat 6e1f7a0` shows only `LICENSE` added. `LICENSE:1` is Apache-2.0 text, not implementation. Repro: `git show --stat --oneline 6e1f7a05af134e510e9a2fa811a978e5eab79e50`.
- BLOCK-2: No validation evidence is available for the claimed terminal sync behavior. `.ai/plan/review-packs/tmux-terminal-sync.json:51` has an empty `validation` list, so tmux control, relay multi-client behavior, iOS rendering, and Codex-mode preservation cannot be verified from the pack.

## Non-Blocking Findings
- none

## Boundary Check
- No out-of-scope files changed: yes, reviewed commit only adds `LICENSE`; blocker is missing scoped implementation, not extra files.
- No forbidden external actions: yes, review used local git/file inspection only.
- Validation evidence reviewed: no, pack recorded none.

## Plan Credibility Notes
- The current implementation does not satisfy the user's primary need: phone can see all Mac terminal windows, create new ones, and keep terminal contents synced both ways. The reviewed commit only adds `LICENSE`, and repo search shows no `tmux-transport.js`, `TmuxTerminalView.swift`, `CodexService+Tmux.swift`, or `TmuxSessionState.swift`.
- The plan is credible only as a tmux-first MVP: phone lists tmux sessions/panes, creates managed tmux sessions, attaches to a selected pane, receives output, sends input, and restores from snapshots on reconnect.
- The plan is not credible for "all Mac terminal windows" as written. It narrows the requirement to tmux sessions, but existing Terminal.app/iTerm2/VS Code terminals that were not launched inside tmux are outside its control.
- The "open new terminal" requirement is underspecified. `tmux new-session -d` creates a headless tmux session, not a visible Mac terminal window. If visible Mac windows are required, the plan needs a macOS Terminal/iTerm launcher that opens a window and attaches to the managed tmux session.
- The relay multi-client estimate is too optimistic. Relay broadcast alone is small, but secure transport is single active phone/session today: `secure-transport.js` has one `activeSession`, one replay cursor, and a fresh handshake clears prior active state. Real multi-client requires per-client secure sessions, replay cursors, counters, and sender routing.
- The terminal rendering estimate is too optimistic. A pure SwiftUI line renderer can handle logs and simple shells, but not robust terminal apps using cursor movement, alternate screen, resize, full ANSI color/style, mouse, or raw mode. A realistic MVP should state those limitations or use a real terminal emulator component.
- The transport design should prefer tmux control mode, `pipe-pane`, or per-pane `capture-pane` snapshots over attaching one `node-pty` client to tmux. The plan's `node-pty spawn tmux attach` approach risks syncing one client view rather than all panes with reliable pane identity.
- The acceptance criteria should be tightened: all sessions means all tmux sessions/panes, not arbitrary OS terminal windows; create means managed tmux session plus optional visible Mac window; sync means output snapshot + live stream + input + resize + reconnect recovery.

## Recommended Plan Changes
- Add Phase 0 proof before iOS work: `tmux list-sessions/list-windows/list-panes`, per-pane snapshot, live output stream, input injection, resize, reconnect restore, and tests with two panes running different commands.
- Define explicit RPC methods: `terminal/list`, `terminal/create`, `terminal/attach`, `terminal/detach`, `terminal/input`, `terminal/resize`, `terminal/snapshot`, and `terminal/kill`.
- Add a wrapper path for MMS/Claude/Codex: launch every AI CLI inside a named tmux session/pane so future terminal sessions are discoverable and syncable.
- Decide whether visible Mac terminal windows are in scope. If yes, add macOS-specific Terminal.app/iTerm2 launch integration and keep it separate from the headless tmux transport.
- Keep Codex mode separate from terminal mode in app state and bridge routing. Do not pretend the existing Codex thread/turn UI can directly host terminal panes without a dedicated terminal state model.
