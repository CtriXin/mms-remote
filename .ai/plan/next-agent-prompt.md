# Next Agent Prompt — SwiftTerm Renderer

你在 `/Users/xin/auto-skills/CtriXin-repo/mms-remote` 工作。始终用简体中文回复，technical terms 保留 English。

## Current Truth

- `main` 是当前真相。
- `main` merge commit: `98072a8 merge: adopt ios terminal running branch`
- merged running commit: `b7196688f9c26c9ed23407d8fd19c00143a0255f`
- old main backup: `codex/backup-main-before-ios-terminal-merge-20260515`
- 用户真机确认：之前一直弹 `Terminal Error` 的问题已消失。

## Task

接入 SwiftTerm，替换当前 iOS Terminal 的 SwiftUI `Text` snapshot viewer。

目标：手机 Terminal 看起来和行为都像真实 terminal，不要“能跑但很丑”的最终状态。

## Key Constraints

- Local-first only: Mac bridge, QR/local relay, tmux-managed panes.
- 不要重新引入 hosted-service 假设或 hardcoded production domains。
- 不要承诺自动接管任意已有 Terminal.app/iTerm2/Ghostty 窗口；可靠边界是 tmux-managed panes。
- 不要跑 Xcode tests，除非用户明确要求。可以跑 targeted Node tests 和 iOS build。
- 保持 Chat/Terminal 共存，Terminal 不要污染 Chat timeline。
- 不要破坏 current visible terminal open behavior：Ghostty/iTerm2 优先 new tab，不复制整套 tabs。

## Relevant Files

- `CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift`
- `CodexMobile/CodexMobile/Models/TerminalModels.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Terminal.swift`
- `mms-remote-bridge/src/tmux-adapter.js`
- `mms-remote-bridge/src/terminal-hub.js`
- `mms-remote-bridge/src/terminal-visible-launcher.js`
- `mms-remote-bridge/test/terminal-hub.test.js`
- `mms-remote-bridge/test/terminal-visible-launcher.test.js`

## Implementation Direction

- Use SwiftTerm as first choice. xterm.js/WKWebView only fallback.
- Keep current SwiftUI text viewer as fallback/debug path while SwiftTerm stabilizes.
- Feed SwiftTerm ANSI-preserved terminal output. Bridge may need `capture-pane -e` path, size negotiation, resize on view geometry, and eventually incremental output.
- Use polished dark terminal theme from start.
- Use existing bundled mono fonts first. Nerd Font support can be a later task, but broken PUA glyph boxes should not dominate UI.
- Add feature flag or fallback switch if needed.

## Acceptance

- ANSI colors render.
- Box drawing, separators, progress bars, Claude/Codex prompt lines, and CJK wide text align on phone.
- Cursor movement, clear screen, shell prompt editing work.
- `top`/`htop`/`less`/`vim` render much better than SwiftUI `Text`, or fail gracefully with clear limitations.
- Existing terminal list/create/attach/input/open-on-Mac flows still work.
- Real phone acceptance: one clean tmux pane, click, `pwd`, Mac/iPhone sync.

## Validation Commands

```bash
cd /Users/xin/auto-skills/CtriXin-repo/mms-remote

node --test \
  mms-remote-bridge/test/terminal-visible-launcher.test.js \
  mms-remote-bridge/test/terminal-hub.test.js \
  mms-remote-bridge/test/mms-remote-cli.test.js

xcodebuild \
  -project CodexMobile/CodexMobile.xcodeproj \
  -scheme CodexMobile \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=4F06CB43-A708-44E5-8418-ABF70A2D4887' \
  -derivedDataPath .build/DerivedData \
  build
```

## Runtime Acceptance Start

```bash
cd /Users/xin/auto-skills/CtriXin-repo/mms-remote
HOME=/Users/xin MMS_REMOTE_DEVICE_STATE_DIR=/Users/xin/.mms-remote node ./mms-remote-bridge/bin/mms-remote.js stop --json || true
pkill -f '/mms-remote-bridge/bin/mms-remote.js' || true
pkill -f 'run-local-mms-remote.sh' || true
pkill -f 'relay/server.js' || true
tmux kill-server || true
tmux new-session -d -s mms-clean -c /Users/xin/auto-skills/CtriXin-repo/mms-remote
```

Then start bridge with the user's preferred real-phone command/environment.
