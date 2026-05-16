# SwiftTerm Real Terminal Execution Plan

Last updated: 2026-05-15 19:50 +0800

## Objective

Build Terminal as a first-class iOS product surface with SwiftTerm as the real terminal renderer. After this plan, managed Terminal panes should feel close to Ghostty/iTerm2 for the mobile use case: live cursor, ANSI/TrueColor, full-screen TUIs, correct keyboard/input, selection/copy/paste, resize, reconnect, and stable Mac tmux coexistence.

This is not a snapshot polish task. The current `tmux capture-pane` + SwiftUI `Text` fallback is only a rescue mode. The final path must stream terminal bytes into SwiftTerm.

## Hard Constraints

- Keep `Chats` and `Terminal` as sibling Bottom Tab Bar products.
- Develop the new SwiftTerm stream renderer inside a third sibling Bottom Tab Bar product named `Swift` until proven; do not disturb the existing `Terminal` / CLI fallback path.
- Do not move Terminal back into Chat toolbar.
- Preserve local-first Bridge, QR pairing, and tmux-managed panes.
- Keep current stable snapshot fallback available behind a diagnostics/fallback path.
- Do not enable SwiftTerm by feeding full `capture-pane` snapshots. That path caused lag, no cursor, no echo.
- Do not run Xcode tests unless user explicitly asks.
- New UI text must be localized in `zh-Hans` and `en`.
- Do not add dependencies without explicit note/gate. If using `node-pty`, `ssh2`, or new Swift packages, HumanGate first.
- Do not promise control of arbitrary existing Ghostty/iTerm2 windows. This project controls tmux-managed panes; visible Mac terminal opening is convenience only.

## Current Facts

- SwiftTerm is already in SwiftPM: `https://github.com/migueldeicaza/SwiftTerm`, version `1.11.2`.
- Local SwiftTerm README states support for VT100/Xterm, Unicode/grapheme clusters, ANSI/256/TrueColor, bold/italic/underline/strikethrough/dim, mouse events, resize, hyperlinks, local process/SSH wiring, Sixel, iTerm2 graphics, Kitty graphics, selection/search APIs, termcast.
- `TerminalView` exposes `feed(byteArray:)`, `feed(text:)`, `resize(cols:rows:)`, delegate `send(source:data:)`, title, cwd, bell, clipboard, scroll, link open, and range change callbacks.
- iOS `TerminalView` already has `UITextInput`/IME handling, hardware keyboard special key mapping, `controlModifier`, `metaModifier`, paste/copy hooks, selection service, scrollback, font/color APIs.
- Current app fallback uses `terminal/snapshot` and `terminal/input` RPC. It cannot produce real cursor, alternate screen, live TUI, OSC, graphics, or correct terminal state.

## Non-Goals

- Full desktop terminal app clone: no split panes UI inside iOS unless backed by tmux panes.
- Arbitrary local iOS shell. iOS cannot run native shell for app use.
- GPU renderer parity with Ghostty. Goal is terminal emulation/display parity, not Ghostty renderer internals.
- Replacing tmux. tmux remains the session manager.
- Remote hosted service.

## Target Architecture

### High-Level

```text
iOS SwiftTerm TerminalView
  -> TerminalTransportActor
  -> secure Bridge WebSocket
  -> terminal stream protocol v2
  -> Bridge TerminalStreamHub
  -> tmux control-mode / output stream
  -> tmux-managed pane
```

### iOS Modules

- `TerminalHubView`: product shell only. Lists sessions/panes, owns selected pane, routes to renderer.
- `TerminalCanvasView`: SwiftUI wrapper around SwiftTerm `TerminalView`.
- `SwiftTermTerminalView`: UIKit bridge; no snapshot feeding.
- `TerminalTransportActor`: durable stream reader/writer, backpressure, reconnect, ordering.
- `TerminalSessionStore`: pane metadata, stream status, last title/cwd, reconnect tokens.
- `TerminalKeyCoordinator`: soft keybar, modifiers, hardware keyboard, paste, bracketed paste.
- `TerminalTheme`: Ghostty/iTerm-inspired themes, font size, cursor style, ANSI palette.
- `TerminalSettingsView`: renderer mode, theme, font, keyboard presets, Mac visible terminal preference.
- `TerminalFallbackSnapshotView`: current stable fallback, explicit label/diagnostic mode only.

### Bridge Modules

- `mms-remote-bridge/src/terminal-stream-hub.js`
- `mms-remote-bridge/src/tmux-control-adapter.js`
- `mms-remote-bridge/src/terminal-protocol.js`
- update `terminal-hub.js` to orchestrate snapshot fallback + stream mode.
- update `tmux-adapter.js` only for shared pane lookup/create/resize/input helpers.
- tests:
  - `terminal-stream-hub.test.js`
  - `tmux-control-adapter.test.js`
  - `terminal-protocol.test.js`
  - existing `terminal-hub.test.js` remains.

## Protocol v2

Keep RPC for CRUD. Add stream channel for bytes.

### RPC Methods

- `terminal/list`
- `terminal/create`
- `terminal/attach`
- `terminal/resize`
- `terminal/input`
- `terminal/kill`
- `terminal/openVisible`
- `terminal/snapshot` fallback only
- new `terminal/stream/start`
- new `terminal/stream/stop`
- new `terminal/stream/replay`
- new `terminal/stream/status`

### Stream Messages

All messages include:

- `type`
- `streamId`
- `paneId`
- `seq`
- `sentAt`

Message types:

- `terminal.stream.ready`: stream accepted, renderer can attach.
- `terminal.stream.output`: base64 raw bytes from pane.
- `terminal.stream.inputAck`: input accepted.
- `terminal.stream.resizeAck`: resize applied.
- `terminal.stream.title`: OSC title update.
- `terminal.stream.cwd`: OSC 7 cwd update.
- `terminal.stream.bell`: bell event.
- `terminal.stream.exit`: pane/session ended.
- `terminal.stream.error`: recoverable/unrecoverable error.
- `terminal.stream.heartbeat`: keepalive.
- `terminal.stream.replayStart` / `replayEnd`: reconnect replay boundary.

### Ordering / Backpressure

- Bridge assigns monotonically increasing `seq` per `streamId`.
- iOS applies output in order.
- iOS buffers out-of-order small gaps for max 250 ms, then requests replay.
- Bridge batches output bytes per animation frame or max 16 KB, whichever first.
- iOS feeds SwiftTerm on main actor, but decoding/batching happens off-main.
- If UI falls behind, coalesce output chunks, never reset terminal.

## Transport Choice

### Preferred: tmux Control Mode

Use tmux control-mode to subscribe to pane output.

Why:

- Keeps tmux as source of truth.
- No new native PTY dependency.
- Supports session persistence.
- Can attach to existing managed pane.
- Emits pane output as stream-like events instead of full snapshots.

Expected implementation:

- Bridge starts a hidden tmux control client for the selected session/pane.
- Parse control-mode events, especially output events.
- Decode tmux-escaped bytes into raw terminal byte stream.
- Forward raw bytes to iOS as base64.
- Use existing tmux commands for input, resize, pane create/kill.
- Maintain one control connection per active iOS pane, or shared per session with pane filtering.

### Fallback: pipe-pane

If control-mode output parsing is unstable, use `tmux pipe-pane -O` to stream pane output to a Bridge process. Keep this behind an adapter interface.

### Last Resort: node-pty

Only if tmux control-mode cannot deliver required fidelity. This adds dependency/risk and needs HumanGate. It would start Bridge-owned PTY sessions, then optionally wrap with tmux.

## SwiftTerm Feature Wiring

### Renderer

- Feed raw output bytes into `TerminalView.feed(byteArray:)`.
- Never feed whole snapshots after initial attach.
- Configure `TerminalOptions`:
  - term name: `xterm-256color` or `xterm-kitty` only after graphics verified.
  - scrollback: default 5000 lines; setting 500/2000/5000/10000.
  - cursor style from settings.
  - tab width default 8.
- Configure colors:
  - Ghostty-like dark theme.
  - iTerm2-like dark theme.
  - Light theme.
  - High contrast theme.
  - User font size 8-18 pt.
- Configure font:
  - default `JetBrains Mono`/existing app mono if bundled.
  - fallback to iOS monospaced system.
  - define policy for Nerd Font/PUA: either bundle font or strip only in snapshot fallback. Real SwiftTerm should render font fallback; do not strip stream bytes.

### Input

- Let SwiftTerm `TerminalView` own IME and text composition.
- Implement `TerminalViewDelegate.send(source:data:)` -> Bridge `terminal/input` bytes.
- Do not mirror TextField input into tmux.
- Use SwiftTerm `controlModifier` and `metaModifier` for soft keybar.
- Support:
  - Enter / Return
  - Esc
  - Tab / Shift-Tab
  - Backspace / Delete
  - Arrows
  - Home / End
  - PageUp / PageDown
  - Ctrl-A..Z
  - Ctrl-[, Ctrl-], Ctrl-\, Ctrl-^, Ctrl-_
  - Alt/Meta + key
  - Option-as-Meta toggle
  - Fn row F1-F12
  - Command shortcuts for copy/paste/select/search where iOS allows.
- Paste:
  - If terminal bracketed paste enabled, wrap with bracketed paste sequences.
  - Else send plain bytes.
  - Large paste chunks 4-16 KB with backpressure.

### Output/Display

- ANSI, 256-color, TrueColor must render.
- Bold, italic, underline, strikethrough, dim must render.
- Alternate screen must work: `vim`, `less`, `top`, `claude`, `codex` TUIs.
- Cursor must be visible and accurate.
- Resize must be cell-based, not guessed by SwiftUI text width.
- Horizontal scroll default off. Instead resize tmux to fit current terminal columns.
- Orientation change triggers cell recompute and Bridge resize.
- Safe area/keyboard changes trigger resize, not just layout shift.

### Selection/Search/Clipboard

- Long press/drag selection via SwiftTerm selection.
- Copy selected text.
- Copy full visible buffer.
- Search current scrollback with SwiftTerm search APIs.
- OSC 52 clipboard:
  - accept only if setting enabled.
  - size limit.
  - user-visible toast/log.

### Hyperlinks/Bell/CWD/Title

- `requestOpenLink` opens URL with confirmation when non-http/s.
- `bell` triggers haptic/audio setting.
- `setTerminalTitle` updates pane header.
- `hostCurrentDirectoryUpdate` updates pane cwd if present.

### Graphics

SwiftTerm claims support for Sixel, iTerm2 graphics, Kitty graphics. Treat as Phase 4+ acceptance, not MVP.

- Test with known commands:
  - `printf` ANSI color grid.
  - `imgcat` for iTerm2 graphics where available.
  - `kitty +kitten icat` / `kittyimg` where available.
  - `img2sixel` where available.
- If graphics fail through tmux, document tmux passthrough requirements. Do not block MVP on graphics unless core TUI is done.

## Product UX Target

Terminal should feel like a real app, not Chat feature.

Screen:

- Full-screen terminal canvas.
- Top compact pane selector + status.
- Bottom optional keybar.
- Keyboard can cover terminal; renderer resizes rows above keyboard.
- No decorative cards around terminal canvas.
- Theme should resemble terminal app: restrained, high contrast, readable.
- Default dark theme OK once renderer has proper color. Snapshot fallback may remain light/dark based on system.

Keybar:

- Row 1: Esc, Tab, Ctrl, Alt, Fn, /, -, arrows cluster toggle.
- Modifier buttons latch visually.
- User presets:
  - Shell
  - Vim
  - Claude/Codex
  - Git
- Quick action menu:
  - Paste
  - Copy
  - Search
  - Clear screen
  - Reset terminal
  - Resize
  - Open on Mac
  - Close pane

Settings:

- Renderer: `SwiftTerm` default, `Snapshot fallback` diagnostic.
- Theme.
- Font size.
- Scrollback lines.
- Option as Meta.
- Backspace sends DEL/Ctrl-H.
- Bracketed paste.
- OSC 52 clipboard.
- Mouse reporting.
- Preferred Mac visible app: Auto, Ghostty, iTerm2, Terminal.app.

## Phase Plan

### Phase 0 — Freeze Baseline / Safety

Purpose: protect working app before deep rewrite.

Current status: partially complete as of 2026-05-15 20:10 +0800. User confirmed the existing app state is stable; `Chats` / `Terminal` tab split and stable snapshot fallback are the rollback baseline. New SwiftTerm stream work should happen in the separate `Swift` tab.

Tasks:

- Record current known-good fallback state in `.ai/plan/current.md`.
- Add feature flag:
  - `terminal.rendererMode = snapshot | swiftterm`
  - default `snapshot` until Phase 3 passes.
- Ensure Terminal tab opens without crash.
- Ensure crash fix for `String(format:)` remains.

Files:

- `TerminalHubView.swift`
- `LocalizationManager.swift`
- `.ai/plan/current.md`
- `.ai/plan/handoff.md`

Acceptance:

- App opens Chat and Terminal.
- Snapshot fallback still usable.
- No startup crash.
- iOS build passes.

Rollback:

- Set `terminal.rendererMode` default back to snapshot.

### Phase 1 — Protocol v2 Contract + Tests

Purpose: lock data shape before implementation.

Tasks:

- Create `terminal-protocol.js`.
- Define schemas for stream start/stop/output/input/resize/error/heartbeat.
- Add Swift models mirroring protocol:
  - `TerminalStreamMessage`
  - `TerminalStreamStatus`
  - `TerminalRendererMode`
  - `TerminalInputPayload`
- Add fixture byte streams:
  - shell prompt
  - ANSI color grid
  - alternate screen enter/exit
  - unicode/emoji/CJK
  - bracketed paste
  - OSC title/CWD
  - OSC 52 clipboard
- Add Node protocol tests.

Files:

- `mms-remote-bridge/src/terminal-protocol.js`
- `mms-remote-bridge/test/terminal-protocol.test.js`
- `CodexMobile/CodexMobile/Models/TerminalModels.swift`

Acceptance:

- Node protocol tests pass.
- Swift models decode sample JSON.
- No behavior change yet.

Rollback:

- Protocol code unused; safe to leave.

### Phase 2 — Bridge Stream Adapter

Purpose: produce real byte stream from tmux-managed pane.

Tasks:

- Implement `tmux-control-adapter.js`.
- Start tmux control-mode hidden client.
- Attach to selected pane/session.
- Parse output events into raw bytes.
- Preserve pane identity and filter output for selected pane.
- Implement stream lifecycle:
  - start
  - heartbeat
  - stop
  - cleanup on disconnect
  - recover on tmux exit
- Implement replay:
  - On attach, optionally send `capture-pane -e` once as initial ANSI-ish snapshot only if needed.
  - Prefer control stream after attach.
  - Mark replay boundaries so iOS can reset only at replay start.
- Implement input:
  - bytes -> tmux pane input.
  - text -> literal input.
  - special key -> tmux key mapping.
  - paste -> bracketed paste aware.
- Implement resize:
  - tmux `resize-window` or pane/window resize as current code.
  - return `resizeAck`.
- Add stream tests with fake tmux process/event fixtures.

Files:

- `mms-remote-bridge/src/tmux-control-adapter.js`
- `mms-remote-bridge/src/terminal-stream-hub.js`
- `mms-remote-bridge/src/terminal-hub.js`
- `mms-remote-bridge/src/tmux-adapter.js`
- `mms-remote-bridge/test/tmux-control-adapter.test.js`
- `mms-remote-bridge/test/terminal-stream-hub.test.js`

Acceptance:

- Can subscribe to pane output.
- Raw ANSI bytes arrive as chunks.
- Input reaches pane.
- Resize reaches pane.
- Disconnect cleans hidden tmux control clients.
- Existing terminal tests still pass.

Rollback:

- Stream methods disabled; existing snapshot RPC remains.

### Phase 3 — iOS SwiftTerm Real Renderer

Purpose: replace fake snapshot renderer with real SwiftTerm byte renderer.

Tasks:

- Rewrite `SwiftTermTerminalView`:
  - no `snapshotText`.
  - expose `feed(bytes:)`.
  - delegate `send(source:data:)` to transport actor.
  - delegate `sizeChanged` to resize.
  - handle title/cwd/bell/link/clipboard.
- Add `TerminalTransportActor`:
  - start stream on attach.
  - decode base64 output.
  - feed SwiftTerm in order.
  - reconnect/resubscribe.
  - backpressure/coalescing.
- Add renderer reset rules:
  - reset only when pane changes or replay start says reset.
  - never reset per snapshot.
- Add SwiftTerm state debug overlay hidden behind dev flag:
  - cols/rows
  - stream seq
  - dropped/replayed count
  - bytes/sec
- Keep snapshot fallback toggle.

Files:

- `CodexMobile/CodexMobile/Views/Terminal/SwiftTermTerminalView.swift`
- `CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift`
- `CodexMobile/CodexMobile/Services/TerminalTransportActor.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Terminal.swift`
- `CodexMobile/CodexMobile/Models/TerminalModels.swift`

Acceptance:

- Shell prompt appears through SwiftTerm.
- Typed text echoes through pane, not local TextField.
- Cursor visible.
- Enter, Backspace, Tab work.
- No lag from reset/feed loops.
- Snapshot fallback still selectable.

Rollback:

- Default renderer back to snapshot.

### Phase 4 — Keyboard / IME / Paste

Purpose: make input feel like Terminal, not chat composer.

Tasks:

- Remove TextField input from SwiftTerm mode.
- Make SwiftTerm view first responder on tap.
- Build `TerminalKeyCoordinator`.
- Build modifier latch UI:
  - Ctrl
  - Alt/Meta
  - Esc
  - Fn
  - Shift for Shift-Tab / selection variants
- Implement keybar actions by calling SwiftTerm input APIs where possible, or sending exact bytes through delegate.
- Validate iOS Chinese IME:
  - composition does not send pinyin early.
  - confirm sends final text.
  - return sends Enter.
- Validate hardware keyboard:
  - arrows
  - Option/Meta
  - Ctrl combos
  - Cmd-C/V behavior
- Implement bracketed paste:
  - detect terminal mode if SwiftTerm exposes it; otherwise setting-controlled.
  - chunk large paste.
- Add paste preview for huge paste > 8 KB.

Files:

- `Views/Terminal/TerminalKeyBarView.swift`
- `Services/TerminalKeyCoordinator.swift`
- `Views/Terminal/SwiftTermTerminalView.swift`
- `Services/CodexService+Terminal.swift`
- `LocalizationManager.swift`

Acceptance:

- Chinese input no pinyin leakage.
- English spaces preserved.
- `cd`, `git status`, `claude`, `codex`, `vim`, `less` usable.
- Ctrl-C stops running program.
- Ctrl-D exits shell/program.
- Tab completion works.
- Paste multi-line command works without corruption.

Rollback:

- Disable SwiftTerm renderer or hide keybar changes behind flag.

### Phase 5 — Visual Fidelity / Theme

Purpose: reach Ghostty/iTerm-like display quality.

Tasks:

- Create theme model:
  - `MMS Dark`
  - `Ghostty Dark`
  - `iTerm2 Dark`
  - `Light`
  - `High Contrast`
- Map ANSI 0-15 palette and 256-color strategy.
- Configure true background/foreground/caret/selection colors.
- Add font settings:
  - size slider 8-18
  - line height policy
  - fallback font policy
- Bundle or document mono font:
  - Prefer existing app mono if already bundled.
  - If adding Nerd Font, HumanGate first because dependency/assets.
- Make canvas stable:
  - no card frame around terminal.
  - no horizontal scroll default.
  - safe area correct.
  - keyboard resize correct.
  - orientation resize correct.
- Add cursor styles:
  - block
  - bar
  - underline
  - blink on/off if SwiftTerm exposes.

Acceptance:

- ANSI 24-bit color test looks correct.
- Claude/Codex TUI not broken.
- Prompt not randomly wraps except when true cols insufficient.
- Header/buttons readable in dark and light mode.
- No text overlap.

Rollback:

- Theme defaults revert; renderer unaffected.

### Phase 6 — Full-Screen TUI Compatibility

Purpose: prove real terminal semantics.

Test matrix:

- `zsh`
- `bash`
- `fish` if installed
- `vim`
- `nano`
- `less`
- `man`
- `top`
- `htop` if installed
- `git add -p`
- `ssh` to another host if available
- `claude`
- `codex`
- `python` REPL
- `node` REPL
- CJK output and emoji
- long prompt paths
- window resize during running TUI
- background/foreground app recover

Tasks:

- Add manual verification checklist.
- Add optional Bridge integration smoke script:
  - create pane
  - stream output
  - send keys
  - resize
  - kill pane
- Capture before/after screenshots in `.ai/plan/progress` only if useful.

Acceptance:

- Alternate screen enters/exits cleanly.
- Cursor remains correct after resize.
- Ctrl-C works inside running TUI.
- Scrollback works after TUI exit.
- No stale duplicate lines from reconnect.

Rollback:

- Flag back to snapshot.

### Phase 7 — Reconnect / Persistence

Purpose: make mobile lifecycle reliable.

Tasks:

- On background:
  - pause UI feed.
  - keep stream if OS allows; otherwise stop gracefully.
- On foreground:
  - stream/status.
  - replay from last seq if possible.
  - otherwise reset + replay snapshot + stream.
- Persist selected pane.
- Persist renderer settings.
- Detect stale pane:
  - pane killed
  - session gone
  - tmux restarted
  - Bridge restarted
- Show non-blocking status:
  - reconnecting
  - stream resumed
  - pane ended
  - fallback available

Acceptance:

- Lock/unlock iPhone no crash.
- Switch Chat/Terminal no stream leak.
- Bridge restart recovers or shows clear reconnect.
- No stale pane cache target like synthetic `mms-N:0.0`.

Rollback:

- Stream stops on background; manual refresh fallback.

### Phase 8 — Mac Visible Terminal App Integration

Purpose: keep Mac-side terminal optional and sane.

Tasks:

- Setting: Auto / Ghostty / iTerm2 / Terminal.app.
- Open selected tmux pane in chosen app.
- Never duplicate existing 10-tab layout.
- Prefer new tab/window with `tmux attach -t session` or `tmux switch-client` command.
- Detect installed apps.
- If selected app missing, fallback Auto.

Acceptance:

- Ghostty opens one new tab/window, not copied layout.
- iTerm2 opens one new tab/window.
- Terminal.app opens one new window/tab.
- Existing iOS stream remains attached.

Rollback:

- Keep existing openVisible disabled or fallback to Terminal.app.

### Phase 9 — Graphics / Advanced SwiftTerm Features

Purpose: enable SwiftTerm high-end features after core works.

Tasks:

- Verify hyperlinks.
- Verify OSC 52 clipboard.
- Verify Sixel.
- Verify iTerm2 graphics.
- Verify Kitty graphics.
- Verify mouse reporting:
  - setting off by default on mobile if it breaks selection.
  - enable for TUIs that need mouse.
- Add user settings for graphics/mouse/clipboard security.

Acceptance:

- Hyperlinks clickable.
- Clipboard safe and user-controlled.
- At least one inline image protocol works if host tools installed.
- Mouse mode does not make normal scrolling unusable.

Rollback:

- Disable graphics/mouse/OSC52 settings.

### Phase 10 — Cleanup / Split Files

Purpose: reduce `TerminalHubView` complexity.

Tasks:

- Split:
  - `TerminalHubView`
  - `TerminalPanePickerView`
  - `TerminalCanvasContainerView`
  - `TerminalKeyBarView`
  - `TerminalCreateSheet`
  - `TerminalSettingsView`
  - `TerminalFallbackSnapshotView`
- Move logic:
  - renderer settings to service/model.
  - key handling to coordinator.
  - stream handling to actor/service.
- Remove debug strings from UI or gate them.
- Update docs/handoff.

Acceptance:

- No single huge Terminal view doing transport + UI + input + formatting.
- Existing behavior unchanged.
- Build passes.

## Global Validation Commands

Run when relevant:

```bash
cd /Users/xin/auto-skills/CtriXin-repo/mms-remote

node --test \
  mms-remote-bridge/test/terminal-hub.test.js \
  mms-remote-bridge/test/terminal-visible-launcher.test.js \
  mms-remote-bridge/test/mms-remote-cli.test.js \
  mms-remote-bridge/test/terminal-protocol.test.js \
  mms-remote-bridge/test/terminal-stream-hub.test.js \
  mms-remote-bridge/test/tmux-control-adapter.test.js

xcodebuild \
  -project CodexMobile/CodexMobile.xcodeproj \
  -scheme CodexMobile \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  build
```

Do not run Xcode tests unless user explicitly asks.

Device install:

```bash
./CodexMobile/scripts/deploy-ios-device.sh \
  --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 \
  --no-launch
```

Console launch:

```bash
xcrun devicectl device process launch \
  --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 \
  --terminate-existing \
  --console \
  --timeout 60 \
  com.mms.remote
```

## Definition Of Done

Core done:

- SwiftTerm is default renderer.
- Snapshot fallback remains available.
- Shell, Claude/Codex, vim/less/top work.
- Cursor accurate.
- Input accurate with Chinese IME and hardware keyboard.
- ANSI/TrueColor correct.
- Resize correct.
- Reconnect reliable.
- No startup crash.
- No terminal error alerts during normal operation.
- Node tests pass.
- iOS build passes.
- Phone smoke passes.

Advanced done:

- Search/copy/selection usable.
- OSC title/cwd/bell/hyperlink wired.
- Preferred Mac visible app setting works.
- Graphics features verified or explicitly gated.

## Wrong Directions To Reject

- Feeding `capture-pane` into SwiftTerm as default.
- More SwiftUI wrapping around snapshot text.
- Per-character TextField live sync.
- Pretending snapshot fallback can become Ghostty/iTerm2-like.
- Turning on SwiftTerm before stream semantics.
- Ignoring input/IME until late.
- Resizing by guessed text width after renderer exists; use SwiftTerm cell dimensions.
- Removing snapshot fallback before real renderer proven.

## Mobius + Looop Dispatch Prompt

Use this prompt as the execution brief:

```text
Repo: /Users/xin/auto-skills/CtriXin-repo/mms-remote
Goal: Implement .ai/plan/swiftterm-terminal-execution-plan.md through Phase 6 first, then pause for phone verification before Phase 7+.

Rules:
- Always respond Chinese-simplified; technical terms English.
- Keep Bottom Tab Bar with Chats/Terminal.
- Preserve local-first Bridge/QR/tmux.
- Do not enable SwiftTerm snapshot feeding.
- SwiftTerm default only after real byte stream works.
- Snapshot fallback must remain.
- Do not run Xcode tests unless user explicitly asks.
- Before adding dependencies, stop at HumanGate.
- Work in small validated slices.
- Each slice records changed files, validation, residual risk in .ai/plan/handoff.md.

First slice:
1. Read .ai/plan/swiftterm-terminal-execution-plan.md.
2. Implement Phase 1 protocol schemas/tests only.
3. Run Node tests for protocol.
4. Do not touch iOS renderer yet.

Second slice:
Implement Bridge stream adapter with fake tmux fixture tests.

Third slice:
Wire iOS SwiftTerm real renderer behind feature flag.

Milestone gate:
Do not make SwiftTerm default until Phase 3 acceptance passes on device.
```
