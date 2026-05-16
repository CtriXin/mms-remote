# SwiftTerm Phase 6 Checklist

Scope: new `Swift` bottom tab only. Existing `Terminal` / CLI fallback must remain unchanged.

## Phase 0-2 Gates

- Stable baseline recorded in `.ai/plan/current.md` and `.ai/plan/handoff.md`.
- `Chats`, `Terminal`, and `Swift` are sibling Bottom Tab Bar entries.
- Bridge protocol v2 stream methods exist: `terminal/stream/start`, `stop`, `replay`, `status`.
- Stream notifications use method `terminal/stream/event` with ordered `terminal.stream.*` messages.
- tmux control-mode output parser decodes octal escapes and filters selected pane.
- Existing CLI terminal RPCs still pass Node tests.

## Phase 3-5 Gates

- `Swift` tab owns the SwiftTerm renderer; `TerminalHubView` default fallback path stays unchanged.
- SwiftTerm receives `terminal.stream.output` base64 bytes, not whole snapshot polling.
- Reset happens on pane/stream change or replay start, not on every update.
- SwiftTerm delegate sends data back through `terminal/input` bytes.
- Soft keybar covers Esc, Tab, Enter, Backspace, Ctrl-C/D/Z, arrows, Ctrl/Alt latches, copy, paste, reset.
- Bracketed paste toggle wraps payload with `ESC[200~` / `ESC[201~` when enabled.
- Font size setting is local to the Swift tab.

## Phase 6 Manual Matrix

Run on phone after installing a build with matching Bridge:

- `zsh`: prompt renders, typed text echoes, Enter works.
- `bash`: prompt renders, Backspace and Tab work.
- `vim`: alternate screen enters/exits; cursor remains correct.
- `less`: scroll/read/quit works.
- `top`: live updates do not duplicate stale lines.
- `git add -p`: single-key prompts work.
- `claude`: TUI layout does not flatten into log text.
- `codex`: TUI layout does not flatten into log text.
- `python` REPL: input/output and Ctrl-D work.
- `node` REPL: input/output and Ctrl-C work.
- CJK/emoji output: width does not visibly drift.
- Resize/orientation: tmux pane resizes to SwiftTerm cols/rows.
- Background/foreground: stream either resumes or shows clear status; no crash.

## Not Done Until Phone Smoke

- Real cursor/TUI fidelity needs device verification.
- Graphics protocols (Sixel/iTerm2/Kitty) stay Phase 9, not blocking Phase 6.

## 2026-05-15 Code Gate Status

Passed before phone smoke:

- Node targeted Bridge suite: 41/41 pass.
- Generic iOS device build: `BUILD SUCCEEDED`.
- Local tmux stream smoke: `terminal/stream/start` + bytes input produced `stream-live`.
- `Swift` tab UI strings added to both zh-Hans and en localization tables.

Still pending:

- Real iPhone Phase 6 manual matrix above.

## 2026-05-15 Device Install Status

- Installed and launched build `23` on `song的iPhone` (`009568BB-3B27-5C91-A94D-34B683F6BCD5`).
- Manual visual matrix still pending because this shell cannot see or operate the physical phone UI.

## 2026-05-15 P1 Blocker Retest Addendum

Code-level retest targets:

- Lifecycle: switching away from `Swift`, closing the view, app background, and disconnect should call stream stop/clear instead of leaving Bridge streams alive.
- Bridge close: relay disconnect/shutdown should call `terminalHub.stopAllStreams({ notify: false })`.
- Replay/live race: live output emitted before or during replay must appear after `replayEnd`, never before `replayStart(reset: true)`.
- Typo compatibility: `terminal/stre/start|stop|replay|status` should route to `terminal/stream/*` handlers.

Device smoke additions:

- Open `Swift`, observe stream output, switch to `Chats`/`Terminal`, then return to `Swift`; no stale duplicate output or growing lag.
- Put app background/foreground while streaming; stream should restart cleanly or show clear status.
- Disconnect/reconnect Bridge while on `Swift`; no persistent stale stream or unsupported `terminal/stre/start` error.

## 2026-05-15 P1 Retest Result

Passed:

- Targeted Bridge terminal Node suite: 45/45 pass.
- Generic iOS Debug build: `BUILD SUCCEEDED`.
- Device build/sign/install: build `24` installed on `song的iPhone`.

Blocked:

- `devicectl` launch was denied because the iPhone was locked, so manual visual matrix remains pending.

## 2026-05-15 Latest Device Build

- Latest installed build: version `1.6.2` build `25` on `song的iPhone`.
- `devicectl` launch still blocked by locked iPhone; open the app manually after unlocking.

## Manual Run Instructions

Before testing:

- Keep the latest Bridge running in tmux session `mms-remote-swiftterm-bridge`.
- If the pairing code is expired, refresh it with:

```bash
tmux kill-session -t mms-remote-swiftterm-bridge 2>/dev/null || true
lsof -tiTCP:9000 -sTCP:LISTEN | xargs -r kill 2>/dev/null || true
tmux new-session -d -s mms-remote-swiftterm-bridge \
  "cd /Users/xin/auto-skills/CtriXin-repo/mms-remote && HOME=/Users/xin RELAY_URL='ws://Xin-MacBook-Pro-16.local:9000/relay' ./run-local-mms-remote.sh"
tmux capture-pane -pt mms-remote-swiftterm-bridge:0 -S -90
```

Phone steps:

- Unlock `song的iPhone`.
- Open CodexMobile version `1.6.2` build `25`.
- Pair with the current Bridge code.
- Open the `Swift` tab and run the Phase 6 Manual Matrix above.

Failure report format:

```text
App version/build:
Bridge pairing code:
Swift tab opened: yes/no
First failing matrix item:
Expected:
Actual:
Steps to reproduce:
Screen recording/screenshot available: yes/no
Bridge log excerpt:
```
