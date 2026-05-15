# Handoff Log

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
