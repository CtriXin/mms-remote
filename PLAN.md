# MMS Remote — Managed Terminal Hub Plan

## 结论

目标可行，但范围必须定义为 **MMS Remote/tmux 管理的 terminal panes**，不是任意已打开的 macOS Terminal.app / iTerm2 / VS Code terminal 窗口。

MVP 目标：
- iPhone 能看到 Mac 上所有由 tmux 管理的 sessions / windows / panes
- iPhone 能打开新的 managed terminal（tmux session/window/pane，可选让 Mac 自动打开 visible terminal attach）
- iPhone 和 Mac 对同一个 pane 的内容双端同步
- iPhone 能向任意 pane 输入命令
- 现有 Codex structured mode 保留，terminal mode 平行新增

不可承诺的目标：
- 自动接管所有已打开、未进入 tmux 的 Terminal.app / iTerm2 / VS Code terminal
- 从外部稳定读取任意 terminal emulator 已消费的 PTY live output / scrollback
- 用纯 SwiftUI Text 做完整 terminal emulator

## 背景

### 现有架构

```text
iPhone <-> WebSocket Relay <-> Mac Bridge <-> Codex CLI (spawn / existing WS)
                          └─ E2EE: X25519 + AES-256-GCM
```

- Relay: `relay/relay.js` — WebSocket 转发，当前偏 1 Mac + 1 Mobile 1:1 会话
- Bridge: `mms-remote-bridge/src/bridge.js` — Mac 侧协调，spawn Codex 或连已有 WS
- Transport: `codex-transport.js` — 已抽象 spawn / websocket 两种 Codex transport
- E2EE: `secure-transport.js` — payload-agnostic，但当前状态模型偏单 active phone
- iOS: `CodexMobile/` — SwiftUI app，transport/E2EE 通用，UI 解析器绑定 Codex 事件

### 用户真实需求

> 手机上能看到电脑上所有终端窗口，且可以开新的。终端内容双端同步。

工程化解释：
- “所有终端窗口”落地为：所有 **managed tmux panes**
- “开新的”落地为：bridge 创建 tmux session/window/pane；可选打开 Mac visible terminal attach 到它
- “双端同步”落地为：Mac 和 iPhone 都连接同一个 tmux pane；输出 snapshot + live stream；输入走 tmux send/input path

### 为什么不能直接接管任意现有 terminal

macOS 没有统一安全 API 让外部 app 可靠读取所有 terminal emulator 的 live PTY 输出、scrollback、状态和输入通道。

不可控来源：
- Terminal.app 直接开的 shell
- iTerm2 直接开的 shell
- VS Code integrated terminal
- 任意 third-party terminal emulator

可控来源：
- tmux sessions/windows/panes
- 由 bridge 创建的 managed PTY/tmux pane
- 由 MMS wrapper 启动并放进 tmux 的 Claude/Codex/shell

## 目标边界

### In Scope

1. Managed terminal hub：所有新 terminal 默认进 tmux。
2. 发现所有 tmux sessions/windows/panes。
3. 按 pane 粒度查看、输入、resize、detach、kill。
4. iPhone 创建新 session/window/pane，指定 cwd 和启动 command。
5. Mac visible terminal attach：创建后可自动打开 Terminal.app/iTerm2 窗口 attach 到同一 tmux pane（可选）。
6. 保留 Codex mode；新增 Terminal mode，不复用 Codex thread/turn UI。
7. E2EE 继续保护 terminal payload。

### Out of Scope

1. 自动读取未进入 tmux 的现有 Terminal.app/iTerm2/VS Code terminal。
2. 第一个 MVP 支持 full-screen terminal apps（vim/htop/lazygit）达到原生级体验。
3. 多手机同时安全同步作为 Phase 1 的必选目标。
4. SSH 产品化、远程服务器管理、多用户权限系统。

## 架构设计

### 新增子系统

```text
                         ┌─ codex-transport.js       (现有，不动)
bridge.js ──mode select──┤
                         ├─ terminal-hub.js          (新增：managed terminal coordinator)
                         └─ tmux-adapter.js          (新增：tmux command/control wrapper)

relay ──secure channel── iPhone Terminal mode
```

原则：
- 不把 terminal logic 塞进 Codex timeline model
- 不把 tmux command 散落在 views 或 bridge dispatch 里
- shared logic 放 service/coordinator
- Codex transport、QR pairing、local relay path 尽量不动

### Pane Address Model

必须按 pane 粒度建模。

```text
TerminalPaneId = session:window.pane

session
  └─ window
       └─ pane
            ├─ paneId
            ├─ title/currentCommand
            ├─ cwd
            ├─ rows/cols
            ├─ active/zoomed/dead flags
            └─ latest snapshot/live stream cursor
```

需要的 tmux commands：
- `tmux list-sessions -F ...`
- `tmux list-windows -a -F ...`
- `tmux list-panes -a -F ...`
- `tmux capture-pane -t <pane> -p -e -J -S <start>`
- `tmux send-keys -t <pane> ...`
- `tmux resize-pane -t <pane> -x <cols> -y <rows>`
- `tmux new-session/new-window/split-window -d -c <cwd> <command>`
- `tmux kill-pane/kill-window/kill-session`

### Output Strategy

Preferred order:
1. **Phase 0/MVP snapshot + diff polling**: `capture-pane` snapshot, then incremental diff/cursor strategy.
2. **Live stream upgrade**: `pipe-pane` or tmux control-mode based stream if Phase 0 shows polling latency/CPU bad.
3. Avoid `node-pty spawn tmux attach` as default path. It nests PTY under tmux attach and makes pane identity/reconnect harder.

Rules:
- Initial attach sends full snapshot.
- Live update batches output every 33-100ms.
- Fast output has byte/message caps.
- Reconnect resends snapshot, then resumes stream.
- Resize is explicit RPC, not inferred from Mac terminal size.

### Input Strategy

手机输入不是普通 text field。需要 terminal key model：
- printable text
- Enter / Backspace / Delete
- Ctrl+C / Ctrl+D / Ctrl+Z / Ctrl+A / Ctrl+E
- Esc / Tab
- arrows / Home / End / PageUp / PageDown
- optional paste bracket mode

MVP 可以先支持：text、Enter、Backspace、Ctrl+C、Ctrl+D、Tab、Esc、arrows。

### iOS Renderer Strategy

纯 SwiftUI `ScrollView + Text` 只能做 log viewer，不是 terminal emulator。

推荐：
- **Preferred**: SwiftTerm，native VT100/ANSI/grid renderer
- **Fallback**: WKWebView + xterm.js
- **Not acceptable for full terminal**: 手写 SwiftUI line list + strip ANSI

MVP 分级：
- Level 1: line-oriented shell/CLI/logs，可用简化 renderer
- Level 2: ANSI color + cursor + resize，使用 SwiftTerm/xterm.js
- Level 3: full-screen apps、alternate screen、mouse，后续增强

### E2EE / Multi-Client Strategy

Relay 广播本身接近现成，但 secure layer 当前偏单 active phone。

Phase 1 默认：
- 一个 iPhone active terminal client
- relay 先不承诺多 mobile 同时 terminal sync

Phase 6 再做：
- per-client secure session
- per-client counters/replay cursors
- sender routing
- slow client backpressure/drop policy

## RPC 草案

Terminal RPC 用新的 namespace，避免绑定 Codex event shape。

```text
terminal/list
terminal/snapshot
terminal/attach
terminal/detach
terminal/input
terminal/resize
terminal/create
terminal/kill
terminal/error
terminal/status
```

示例字段：

```json
{
  "type": "terminal/input",
  "paneId": "dev:1.0",
  "input": {
    "kind": "key",
    "key": "ctrl-c"
  }
}
```

```json
{
  "type": "terminal/snapshot",
  "paneId": "dev:1.0",
  "rows": 32,
  "cols": 96,
  "content": "...",
  "cursor": { "row": 31, "col": 0 }
}
```

## 实现阶段

### 当前落地状态（2026-05-15）

- Phase 0/1/2 MVP 已落地：tmux adapter、bridge terminal RPC、iOS basic terminal hub、CLI smoke commands。
- Phase 4 中的 “Create New Terminal + Visible Mac Window” 已推进：手机/CLI 创建 managed terminal 时可请求 Mac 打开 Terminal.app 窗口 attach 到同一 tmux session/pane；已有 pane 也可再打开到 Mac。
- 验收前 smoke 已落地：`mms-remote terminal smoke --json` 会创建 managed tmux session、验证 snapshot/input、自动清理。
- 仍未完成 Full：真实 terminal renderer、MMS wrapper integration、多 iOS client hardening。

### Phase 0: Mac-only Proof

目标：先证明 tmux pane 管理链路可行，不碰 iOS 大改。

改动文件：
- `mms-remote-bridge/src/tmux-adapter.js`（新增）
- `mms-remote-bridge/src/terminal-hub.js`（新增）
- `mms-remote-bridge/test/terminal-hub.test.js`（新增，Node test）

验证：
1. 创建 test session，两个 panes 跑不同 commands。
2. `list` 能返回 session/window/pane。
3. `snapshot` 能读指定 pane。
4. `input` 能把命令送到指定 pane。
5. `resize` 能改变 pane size。
6. kill/cleanup 不留 tmux 垃圾 session。

Exit criteria：
- CLI/Node test 证明 `list -> snapshot -> input -> snapshot` 全通
- 处理 pane name collision
- 不依赖 `node-pty`

### Phase 1: Bridge Terminal Mode

目标：bridge 能通过 secure channel 提供 terminal RPC。

改动文件：
- `mms-remote-bridge/src/bridge.js`
- `mms-remote-bridge/bin/mms-remote.js`
- `mms-remote-bridge/src/terminal-hub.js`

功能：
- `--mode codex|terminal`
- terminal RPC dispatch
- attach/detach lifecycle
- batching/throttle
- error envelope

验收：
- 本地 relay + bridge 下，模拟 iPhone client 可以 list panes、attach pane、send input、收到 snapshot/update。

### Phase 2: iOS Terminal State + Basic UI

目标：iPhone 可以看到 pane list，点进去看 line-oriented output，发基础输入。

新增/修改文件：
- `CodexMobile/CodexMobile/Models/TerminalModels.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Terminal.swift`
- `CodexMobile/CodexMobile/Views/TerminalPaneListView.swift`
- `CodexMobile/CodexMobile/Views/TerminalPaneView.swift`
- `CodexMobile/CodexMobile/Services/CodexService+Transport.swift`

MVP renderer：
- 可先做 line-oriented viewer，仅支持 shell/CLI/logs
- 明确不支持 vim/htop/lazygit 等 full-screen app

MVP input：
- text / Enter / Backspace / Ctrl+C / Ctrl+D / Tab / Esc / arrows

验收：
- iPhone 能打开 managed pane
- iPhone 输入 `pwd` / `ls` / `echo hi`，Mac tmux pane 出现结果
- Mac 端输入，iPhone 更新

### Phase 3: Real Terminal Renderer

目标：把 basic viewer 升级成真实 terminal。

推荐路线：
- 首选 SwiftTerm
- 备选 WKWebView + xterm.js

需要支持：
- ANSI/VT100 parsing
- character grid
- cursor movement
- clear screen
- resize rows/cols
- alternate screen 基础支持

验收：
- `top`/`htop` 类刷新不刷屏成垃圾文本
- shell prompt editing 正常
- progress bar / `\r` 覆盖显示正常

### Phase 4: Create New Terminal + Visible Mac Window

目标：手机可以开新 terminal，并可选择 Mac 是否打开 visible terminal 窗口。

功能：
- create session/window/pane
- choose cwd
- choose command: shell / codex / claude / custom command
- optional macOS launcher:
  - Terminal.app open new window attach tmux pane
  - iTerm2 integration 后续可选

验收：
- iPhone 点 “New Terminal” 后，Mac tmux 有新 pane
- 可选打开 Mac visible window attach 到该 pane
- 两端输入/输出同步

### Phase 5: MMS Wrapper Integration

目标：MMS/Claude/Codex 从入口处变成 discoverable managed terminal。

功能：
- `mms-remote terminal new --command codex --cwd <path>`
- existing MMS launcher 可选择包进 tmux session/pane
- pane metadata 标记 provider/model/cwd/title

验收：
- 通过 MMS Remote 创建的 Codex/Claude session 都出现在 iPhone terminal list
- model/provider 选择不受影响，因为 terminal hub 只管 PTY/tmux 层

### Phase 6: Multi-Client Hardening

目标：多个 phones/tablets 同时看同一 pane。

需要解决：
- relay client backpressure
- per-client secure sessions
- per-client replay cursor
- duplicate input ordering
- sender attribution

验收：
- 两台 iOS 设备同时 attach 同一 pane，都能收到输出
- 任一设备输入后，另一台和 Mac 都同步
- 慢客户端不会拖垮 relay/bridge

## 风险与处理

| 风险 | 级别 | 处理 |
|------|------|------|
| 误解“所有终端窗口” | 高 | 明确只支持 managed tmux panes；非 tmux 终端需迁移/attach |
| iOS renderer 工作量 | 高 | 不手写 full terminal；用 SwiftTerm 或 xterm.js |
| `node-pty` 编译/嵌套 PTY | 中 | MVP 不依赖 node-pty；优先 tmux native commands |
| 输出高频刷爆 relay | 中 | batching、byte cap、drop policy、snapshot recovery |
| 多端输入 interleave | 中 | MVP 单 active input；后续 sender/order policy |
| secure transport 多 client | 中 | Phase 6 单独做，不混进 MVP |
| tmux 不存在 | 低 | 启动时检查 `tmux -V`，提示安装；本机已有 tmux 3.6a |

## 不需要动的部分

- `codex-transport.js`：保持 Codex structured mode
- QR pairing UX：保持现状
- local relay pairing/reconnect 主流程：尽量不动
- existing timeline/thread/turn rendering：不复用给 terminal mode

## 验收标准

### MVP 验收

1. iPhone 能看到所有 tmux sessions/windows/panes。
2. iPhone 能 attach 任意 pane。
3. iPhone 能看到 pane snapshot 和后续输出。
4. iPhone 能发送基础输入到 pane。
5. Mac 和 iPhone 对同一 managed pane 双端同步。
6. iPhone 能创建新 managed terminal。
7. Codex structured mode 不回归。

### 验收入口

```bash
cd mms-remote-bridge
node ./bin/mms-remote.js terminal smoke --json
node ./bin/mms-remote.js terminal create --name mms-acceptance --cwd "$PWD" --open-visible --json
node ./bin/mms-remote.js terminal list --json
```

手工验收：
1. Mac 先跑 `npm start` 或 `node ./bin/mms-remote.js up`，手机连上 bridge。
2. 手机进 Terminal，确认能看到 managed pane list。
3. 手机创建 terminal，保持 `Open on Mac` 开启，确认 Mac Terminal.app 弹窗。
4. 手机输入 `echo phone_ok`，Mac 同 pane 能看到；Mac 输入 `echo mac_ok`，手机 snapshot/poll 能看到。
5. 对已有 pane 点顶部 display 按钮，确认能重新打开到 Mac。

### Full 验收

1. 真实 terminal renderer 支持 ANSI、cursor、resize、alternate screen。
2. 手机 terminal input bar 支持常用 modifier/special keys。
3. 新建 terminal 可选打开 Mac visible terminal window。
4. MMS/Claude/Codex wrapper 创建的 sessions 全部自动 discover。
5. 多 iOS client 同时连接稳定。

## 工作量估算

| 部分 | 估算 | 说明 |
|------|------|------|
| Phase 0 Mac-only PoC | 1-2 天 | tmux adapter + tests |
| Bridge terminal mode | 1-2 天 | RPC dispatch + batching |
| iOS basic terminal UI | 2-4 天 | list/view/input state |
| Real terminal renderer | 3-7 天 | SwiftTerm/xterm.js integration |
| Create terminal + visible Mac window | 1-3 天 | tmux create + AppleScript/iTerm optional |
| MMS wrapper integration | 1-2 天 | launch path + metadata |
| Multi-client hardening | 3-5 天 | secure per-client + backpressure |

MVP：约 4-8 天。
Full：约 2-4 周。
