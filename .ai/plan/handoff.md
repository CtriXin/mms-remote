# Handoff Log

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
