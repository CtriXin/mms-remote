# Current Handoff — MMS Remote Terminal

- timestamp: 2026-05-15 04:15 -0400
- owner: Codex
- CLI: codex
- model: GPT-5
- task_id: terminal-rescue-handoff
- status: paused; user will merge a working branch from another worktree
- next_action: after merge, inspect the incoming branch diff, keep the working terminal path, and resume with small validated iterations only

## Goal

Phone Terminal must control Mac tmux-managed terminal panes:

- iOS sees Mac managed tmux sessions/windows/panes.
- iOS can open/create a new managed terminal.
- Mac and iOS share the same pane content and input path.
- Codex Chat and Terminal remain separate app entry points.
- Short CLI remains simple: `mmr join [name]` / `mms-remote terminal join [name]`.
- Later: keyboard shortcuts, better terminal renderer/theme, visible Mac terminal support, and safer multi-device relay support.

## Hard Boundary

Do not promise automatic capture of arbitrary existing Terminal.app/iTerm2/Ghostty panes unless they join tmux. The reliable product boundary is tmux-managed panes.

## Known Good Anchor

User-identified known-good commit:

- `3fa85e4bcb8189636fa044832f2558beb85627c7` — `feat(cli): add mmr join shortcut`

A rescue worktree was created at:

- `/Users/xin/auto-skills/CtriXin-repo/mms-remote-rescue-3fa`
- branch: `rescue/terminal-3fa-clean`
- base: `3fa85e4`
- extra patch only: `aaa446a` Xcode `confirmationDialog` compile fix + version bump to build `119`
- validation before interruption: `node --test mms-remote-bridge/test/terminal-hub.test.js` passed; generic iOS build passed

## Current Main State

Current `main` includes multiple failed rescue attempts through:

- `5bf130c fix(ios): clear terminal cache on entry`

User reported it still fails. Do not keep patching from assumptions on this state. Prefer merging the external working branch, then compare against `3fa85e4` and current `main`.

## Recent Failure Pattern

Observed symptoms:

- iOS showed many stale terminal tabs.
- Clicking tabs produced `Terminal Error`.
- Earlier logs showed stale synthetic targets like `mms-1:0.0`, `mms-2:0.0` and errors like `Terminal pane target is required` / `Unknown terminal pane`.
- Later Bridge logs only showed `terminal/list ok`, no fresh `terminal/attach` failure, suggesting iOS stale state or alert handling also contributed.
- Clearing tmux and Bridge runtime did not restore confidence.

## Runtime Stop State

Before this handoff, the current Bridge/relay/tmux runtime was stopped/cleared by command:

- `mms-remote.js stop`
- killed `mms-remote`, `run-local-mms-remote`, `relay/server.js` leftovers
- `tmux kill-server`
- truncated `/Users/xin/.mms-remote/logs/bridge.stdout.log` and `bridge.stderr.log`

Do not assume any running Bridge is the correct one after the user merges another branch. Re-check before testing.

## Next Action

1. Wait for user to merge the working branch.
2. Run `git status -sb && git log --oneline -8`.
3. Inspect terminal-related diff only.
4. Start clean runtime from the merged branch.
5. Verify with one pane, one phone install, one click, one input.
6. Only then continue feature iteration.

## Blockers / Risks

- Multiple Xcode/worktree builds can install the same bundle id `com.mms.remote`; user may be running an older build unless version/build is checked.
- Multiple Bridge launch modes existed: launchd `run-service`, foreground `run`, and local relay script. Only one should be active during verification.
- Multiple tmux sessions/panes can look like app bugs. Acceptance should start from one clean `mms-clean` pane.
- Do not hide terminal RPC errors. Log method + target + result counts on Bridge.
