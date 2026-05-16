# MMSChat Execution Plan

- Timestamp: 2026-05-16
- Owner: Codex
- CLI: Codex CLI
- Model: GPT-5
- Task ID: mmschat-plan-2026-05-16
- Status: draft-for-human-review
- Next action: 人工审核本计划，确认 MVP 边界后再开并行 worktree 执行。

## 0. TL;DR

我们要做的不是再造一个完整 `Terminal`，而是新增一个 `MMSChat`：只面向 MMS 启动的 Claude/agent sessions，提供类似 Codex Chat 的列表和详情页。

核心原则：

```text
Claude native session = 记忆 source of truth
MMSChat = session index + status + transcript cache + Codex-like UI
Terminal = 真实 shell/PTY 控制面板，不和 MMSChat 混用 UI 边界
```

最小可落地范围：

- iPhone 能看到 MMS 启动的 Claude sessions。
- 每个 session 显示 title / cwd / model / provider / 状态 / 最近输出。
- 点进去能看到近似 Chat 的 transcript 视图。
- 能 `Open on Mac`、复制 resume command、kill session。
- 如果启用手机发送，消息必须进入 Claude native session，否则 Claude 不会记忆。
- 不把 `mmschat` 做成第二份完整聊天数据库。

## 1. 当前上下文

### 1.1 Repo 和产品当前状态

当前 repo：

```text
/Users/xin/auto-skills/CtriXin-repo/mms-remote
```

分支：

```text
main
```

当前 iOS 版本已从用户提到的：

```text
1.7.14 (50)
```

在本轮小改中 bump 到：

```text
1.7.15 (51)
```

当前产品已有能力：

- iPhone 连接 Mac bridge。
- Codex Chat 视图显示本地 Codex sessions / threads。
- Terminal tab 可管理 Mac 上 tmux sessions/windows/panes。
- MMS Remote 已经是 local-first；不应重新引入 hosted-service 假设。
- Terminal 管理范围已经明确：只管理 tmux 可控 pane，不接管任意已打开的普通 Mac terminal。

### 1.2 用户最新需求

用户希望新增一个类似 Codex Chat 的界面，但对象不是 Codex thread，而是 MMS 启动的 Claude sessions。

用户命名倾向：

```text
MMSChat
```

用户希望达到的体验：

- Mac 端继续正常使用 Claude/agent。
- iPhone 端能看到 MMS 启动的 Claude session 状态和输出。
- iPhone 端 UI 体验接近 Codex Chat：列表、按 project/cwd 分组、session 详情、状态和 transcript。
- 支持 MMS 启动不同 model/provider，例如 `mimo`、`kimi`、Anthropic 等。
- resume 时最好继续使用对应 launch profile，或者至少清楚显示当前 provider/model。
- 不希望 MMSChat 和 Terminal 功能边界混乱。
- 不希望创建第二套完整 chat database，导致 Claude native session 与 MMSChat 记录不同步。

### 1.3 已确认的重要认知

#### 隔离环境

用户修正后的理解是正确的：隔离环境主要是本次启动会话的 runtime profile，例如：

```text
provider / model / baseUrl / key ref / env / cwd
```

隔离环境删除通常没问题，只要不要删除 Claude native session/history。

#### Claude native session

Claude session 应存在于 Claude 自己的持久位置，不应随 MMS 临时启动配置一起删除。

目标设计中：

```text
Claude native session 持久保存记忆
MMSChat 只保存 session index/cache
```

#### model/provider resume

用户目前做法：用不同 model 启动，然后 resume。

结论：方向可行，但需要实测不同 provider/model 对 `claude --resume <id>` 的兼容性。

需要保存的不是 token 本身，而是可恢复 profile：

```text
provider
model
baseUrl/profileName
authSecretRef
cwd
nativeClaudeSessionId
launch command/env fingerprint
```

#### 手机输入是否需要进入 Claude

如果希望 Claude “知道手机上聊过什么” 并且 `resume` 后仍有记忆，那么手机输入必须进入 Claude native session。

两种路径：

```text
A. 发送到 live Claude 进程 / PTY / stdin
   -> Claude 立即知道
   -> native session 立即记录
   -> resume 后大概率保留

B. 不发送给 Claude，只存 MMSChat sidecar
   -> Claude 当下不知道
   -> resume 不会原生知道
   -> 需要 MMSChat 在下一次启动/resume 时注入 summary/transcript
```

推荐路径：A，但 UI 不表现为 Terminal；MMSChat 内部可写 PTY/stdin，外部只显示 Chat 操作。

### 1.4 已知 Codex Chat 现象

当前 Codex 手机端和 Mac Codex.app 存在已知现象：

- 手机端发送到同一个 Codex thread 后，Codex runtime 处理时知道该输入。
- Mac Codex.app UI 不一定 live reload 显示手机输入。
- 不显示不等于 runtime 不知道。
- Mac app 可能需要刷新/重开 thread 才看到新内容。

这对 MMSChat 的启发：

```text
UI 是否实时互相显示，不应作为记忆 source of truth。
真正重要的是输入是否进入 native session。
```

## 2. 为什么要改

### 2.1 当前 Terminal 功能解决的是“控制”问题

Terminal tab 已经能：

- list tmux sessions/windows/panes
- attach/snapshot/input/resize/kill
- 在 Mac 打开可见 terminal
- 用 tmux 保持 Claude/Codex 进程不随手机断开而死

但 Terminal UI 对 Claude 这种 conversational agent 不够友好：

- 输出是 terminal transcript，不是 message timeline。
- 用户关心 session/title/model/status，而不是 pane/window 控制细节。
- 手机上想看“Claude 会话”，不是操作 shell。
- Terminal 的 resize/copy-mode/attach/detach 概念会增加学习成本。

### 2.2 用户真正需要的是“会话状态和继续工作”

用户期望：

- 在手机上看到 MMS 启动的 Claude sessions。
- 知道哪个 session 在哪个 project/cwd 中运行。
- 知道用的什么 model/provider。
- 能在手机上查看最近对话/输出。
- 必要时能继续发送消息。
- 在 Mac 端可继续同一 session。
- 关闭后 resume 仍能恢复记忆。

这和 Codex Chat 的产品心智一致，所以应新增 MMSChat，而不是继续扩大 Terminal。

### 2.3 避免功能边界混乱

必须区分：

```text
Terminal:
  面向 shell/PTY/tmux，用户看到完整 terminal，允许 send-keys、resize、copy-mode。

MMSChat:
  面向 Claude/agent session，用户看到 Chat-like timeline，不暴露 shell 控制。
```

即使 MMSChat 内部通过 PTY/stdin 发送消息，也不应暴露 terminal 操作按钮，以免产品边界混乱。

## 3. 当前已经改了哪些

### 3.1 已完成：tmux cheatsheet

已新增 `tmux 速查`，帮助用户理解：

- tmux 结构：Ghostty -> tmux client -> tmux pane -> Claude/Codex
- 如何进入/重新接入
- 如何 detach 保留 Claude 进程
- 如何滚动历史
- 如何修复 resize 后的小窗口/点点背景
- 如何真正关闭 session/pane/process

已涉及文件：

```text
CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift
CodexMobile/CodexMobile/Views/SettingsView.swift
CodexMobile/CodexMobile/Services/LocalizationManager.swift
CodexMobile/CodexMobile.xcodeproj/project.pbxproj
```

关键入口：

```text
Settings -> Terminal -> tmux 速查
```

版本号已按项目规则从：

```text
1.7.14 (50)
```

更新到：

```text
1.7.15 (51)
```

验证记录：

```text
git diff --check 通过
Swift parse 通过
未运行 Xcode tests（项目规则：不主动运行 Xcode tests）
```

### 3.2 本文档新增

本文件：

```text
.ai/plan/mmschat-execution-plan.md
```

用途：

- 给 human review。
- 给并行 worktree 任务拆分。
- 给后续 agent/Claude/Codex/Hive 继续执行。

## 4. 目标架构

### 4.1 总体结构

```text
iPhone MMSChat UI
  -> secure RPC over existing bridge
    -> mmschat coordinator
      -> mmschat registry/index/cache
      -> Claude launcher/profile resolver
      -> tmux/PTY/native transcript observer
      -> Claude native session/history
```

### 4.2 Source of truth

必须明确：

```text
Claude native session/history = 记忆 source of truth
MMSChat registry/index = 展示索引 + 状态缓存 + 可恢复 metadata
MMSChat transcript cache = 展示加速/离线预览，不作为最终真相
```

禁止设计成：

```text
MMSChat full chat DB 与 Claude native session 双向同步
```

原因：

- 双数据库会出现不一致。
- 删除语义复杂。
- resume 到底读谁会不清晰。
- provider/model 切换后难以保证上下文一致。

### 4.3 持久化数据模型

建议新增 bridge-side registry 文件，位置待定，例如：

```text
~/.mms-remote/mmschat/sessions.json
~/.mms-remote/mmschat/transcript-cache/<mmschatId>.jsonl
```

或复用已有 bridge device state 目录，但需要确认不会被 reset-pairing 清掉。

MMSChatSession 建议字段：

```json
{
  "mmschatId": "mmschat_...",
  "nativeClaudeSessionId": "...",
  "title": "...",
  "cwd": "/Users/xin/...",
  "project": "mms-remote",
  "agent": "claude",
  "provider": "kimi|mimo|anthropic|custom",
  "model": "...",
  "launchProfileName": "...",
  "launchProfileFingerprint": "...",
  "authSecretRef": "keychain-or-profile-ref-only",
  "tmuxPaneId": "%42",
  "tmuxSessionName": "mms-...",
  "pid": 12345,
  "status": "running|idle|dead|needs-resume|unknown",
  "createdAt": "ISO8601",
  "lastActivityAt": "ISO8601",
  "lastPreviewText": "...",
  "lastTokenOrCostText": "...",
  "hidden": false
}
```

不应存：

```text
live auth token 明文
完整 secrets
relay sessionId
bearer-like pairing identifier
```

### 4.4 删除语义

UI 必须分开三种操作：

```text
Hide / 从 MMSChat 列表隐藏
  - 只改 mmschat index hidden=true
  - 不删 Claude native session
  - 不杀 live process

Delete MMSChat cache / 删除展示缓存
  - 删除 mmschat transcript cache
  - 不删 Claude native session
  - 下次可从 native transcript/tmux 重新恢复部分展示

Destroy Session / 销毁会话
  - 杀 tmux pane/process
  - 可选删除 Claude native session（默认不要）
  - 危险操作，必须确认
```

默认推荐：

```text
默认关闭按钮 = Stop/Kill live process，不删除 native session
删除 native session = 单独高级危险操作
```

### 4.5 model/provider 规则

MMSChat 必须保存 launch profile metadata。

Resume 策略：

```text
live process exists:
  attach/observe current process
  model/provider = live process current state

live process missing and user taps resume:
  use saved launchProfileName/provider/model/baseUrl profile
  run claude --resume <nativeClaudeSessionId>
  update pid/tmuxPane/status
```

重要不确定点：

```text
Claude CLI 是否允许 native session 用不同 provider/model resume？
```

需要 S 任务实测。

## 5. RPC / Protocol 草案

### 5.1 新 namespace

建议新增独立 namespace：

```text
mmschat/list
mmschat/detail
mmschat/attach
mmschat/send
mmschat/resume
mmschat/openVisible
mmschat/kill
mmschat/hide
mmschat/cache/clear
mmschat/status
```

不要复用 `terminal/*` RPC，避免 UI/语义混淆。

### 5.2 `mmschat/list`

请求：

```json
{
  "method": "mmschat/list",
  "params": {
    "includeHidden": false,
    "project": "optional"
  }
}
```

响应：

```json
{
  "sessions": [
    {
      "mmschatId": "...",
      "title": "...",
      "cwd": "...",
      "project": "...",
      "agent": "claude",
      "provider": "kimi",
      "model": "...",
      "status": "running",
      "lastActivityAt": "...",
      "preview": "..."
    }
  ]
}
```

### 5.3 `mmschat/detail`

请求：

```json
{
  "method": "mmschat/detail",
  "params": {
    "mmschatId": "...",
    "limit": 200
  }
}
```

响应：

```json
{
  "session": {...},
  "messages": [
    {
      "id": "...",
      "role": "user|assistant|system|tool|terminal",
      "text": "...",
      "timestamp": "...",
      "source": "native|tmux|cache|hook"
    }
  ],
  "rawTranscriptAvailable": true,
  "live": true
}
```

### 5.4 `mmschat/send`

请求：

```json
{
  "method": "mmschat/send",
  "params": {
    "mmschatId": "...",
    "text": "...",
    "mode": "live-or-resume"
  }
}
```

行为：

```text
if live Claude process exists:
  send text into controlled Claude input path
  append/send Enter
  mark pending user message in cache

else:
  if mode == live-or-resume:
    resume native session via saved launch profile
    send text
  else:
    return needs-resume error
```

### 5.5 `mmschat/openVisible`

打开 Mac terminal attached to tmux pane。

与 Terminal 的 `openVisible` 类似，但仍保持 MMSChat UI 不暴露 shell 控制。

### 5.6 `mmschat/kill`

默认语义：

```text
kill live process/pane only
keep native Claude session/history
keep mmschat index unless user also hides/deletes
```

## 6. 详细 P 任务拆分

本计划建议 8 个 P 任务。

### P0 - Protocol 和数据模型定稿

目标：冻结 `mmschat` 最小协议和数据模型。

Owner 建议：integration owner / host。

写范围：

```text
Docs 或 .ai/plan 内协议文档
mms-remote-bridge/src/mmschat-protocol.js 或类似新增文件
CodexMobile/CodexMobile/Models/MMSChatModels.swift
```

产物：

- `MMSChatSession` 数据模型。
- RPC method names。
- 删除语义。
- error codes。
- 不存 secrets 的规则。

验收：

- 后端和 iOS 可基于 mock 独立开发。
- JSON shape 稳定。

### P1 - Bridge-side MMSChat registry

目标：保存 MMS 启动的 Claude sessions 的 index/cache。

写范围：

```text
mms-remote-bridge/src/mmschat-registry.js
mms-remote-bridge/src/mmschat-store.js
mms-remote-bridge/test/mmschat-registry.test.js
mms-remote-bridge/test/mmschat-store.test.js
```

功能：

- register/update/list/hide/clear cache。
- status transitions：running/idle/dead/needs-resume。
- lastActivity/preview 更新。
- 不保存 auth token 明文。

验收：

- Node tests 覆盖 register/list/update/hide/delete-cache。
- corrupt store 能 fallback 或报明确错误。

### P2 - MMS Claude launcher integration

目标：MMS 启动 Claude 时自动登记 MMSChat session。

写范围：

```text
mms-remote-bridge/src/mmschat-launcher.js
mms-remote-bridge/src/terminal-hub.js 或独立 launcher entry
mms-remote-bridge/bin/mms-remote.js
```

功能：

- 新建 Claude session 时记录 provider/model/profile/cwd/native session id。
- 能从 stdout/stderr/tmux title/known pattern 抓 nativeClaudeSessionId。
- 如果 native session id 初期拿不到，允许先 `pending`，后续更新。

验收：

- `mms-remote mmschat create --agent claude --model ...` 可产生 registry entry。
- 不影响现有 terminal create/join。

### P3 - Transcript/live output observation

目标：让 MMSChat 详情页能显示输出。

写范围：

```text
mms-remote-bridge/src/mmschat-transcript.js
mms-remote-bridge/src/mmschat-parser.js
mms-remote-bridge/test/mmschat-transcript.test.js
```

分阶段：

```text
MVP:
  从 tmux capture/control stream 获取 raw transcript。
  做轻量清洗，生成 terminal/assistant-ish blocks。

后续:
  接 Claude hook/native transcript，提升 user/assistant/tool 分块准确度。
```

验收：

- mmschat/detail 能返回最近 N 条/块。
- 不因为 terminal ANSI/box drawing 崩溃。
- preview 能稳定更新。

### P4 - iOS MMSChat list/detail UI

目标：手机端新增 Codex-like MMSChat 页面。

写范围：

```text
CodexMobile/CodexMobile/Models/MMSChatModels.swift
CodexMobile/CodexMobile/Services/CodexService+MMSChat.swift
CodexMobile/CodexMobile/Views/MMSChat/MMSChatListView.swift
CodexMobile/CodexMobile/Views/MMSChat/MMSChatDetailView.swift
```

功能：

- 按 project/cwd 分组显示 sessions。
- 展示 title/status/model/provider/lastActivity/preview。
- 详情显示 transcript blocks。
- 空态和错误态本地化。

验收：

- 可用 mock 数据开发。
- 不修改现有 Codex timeline 核心逻辑。

### P5 - Action integration：send/resume/open/kill

目标：MMSChat 可操作 session，但不变成 Terminal。

写范围：

```text
mms-remote-bridge/src/mmschat-hub.js
CodexMobile/CodexMobile/Services/CodexService+MMSChat.swift
CodexMobile/CodexMobile/Views/MMSChat/*
```

功能：

- `Open on Mac`
- `Copy resume command`
- `Kill live process`
- 可选 `Send message`
- dead session 时 `Resume and send`

验收：

- send 成功进入 Claude native session。
- kill 不删除 native session。
- resume 使用 saved profile。

### P6 - model/provider profile correctness

目标：确保不同 provider/model 下创建和 resume 行为可解释。

写范围：

```text
mms-remote-bridge/src/mmschat-profile.js
mms-remote-bridge/test/mmschat-profile.test.js
```

功能：

- 保存 profile name/fingerprint。
- secret 只保存 ref。
- resume 时恢复 env。
- UI 显示 last known model/provider 和 current live model/provider。

验收：

- kimi/mimo/anthropic 三类 profile 至少有 dry-run 或 fixture。
- 不泄露 key 到 logs/store。

### P7 - Integration, validation, and release polish

目标：把上述模块合并进产品入口并验证。

写范围：

```text
mms-remote-bridge/src/bridge.js
mms-remote-bridge/src/index.js
CodexMobile/CodexMobile/ContentView.swift 或 Tab/Sidebar 入口
CodexMobile/CodexMobile/Services/LocalizationManager.swift
CodexMobile/CodexMobile.xcodeproj/project.pbxproj
```

职责：

- 统一入口。
- 本地化。
- 版本 bump。
- merge 冲突处理。
- release notes/Settings help。

验收：

- 不回归 Codex Chat。
- 不回归 Terminal。
- mmschat MVP 手工链路跑通。

## 7. S 任务 / Spike 任务

有 S 任务。建议 4 个。

### S0 - Claude native transcript/source research

问题：Claude native session/transcript 是否可稳定读取？格式如何？是否含 role/tool/model/status？

产物：

```text
.ai/plan/progress/mmschat-s0-transcript-source.md
```

验收：

- 明确 MVP 读取 tmux，还是读取 native transcript，还是 hook。
- 给出 fallback 顺序。

### S1 - Provider/model resume 实测

问题：同一个 Claude native session 能否用不同 provider/model resume？

测试矩阵：

```text
create with kimi -> resume with kimi
create with kimi -> resume with mimo
create with mimo -> resume with kimi
create with anthropic -> resume with custom provider
```

验收：

- 成功/失败矩阵。
- 失败时 UI 文案和 fallback 策略。

### S2 - Live input safety spike

问题：MMSChat 发送消息到 live Claude 进程时，如何避免和 Mac 端同时输入冲突？

选项：

```text
A. 简单 send-keys：低成本，高冲突风险。
B. 检测 prompt idle 再发送：中成本。
C. 专门 PTY/session owner：较高成本。
D. dead/resume-only send：低冲突，但实时性差。
```

验收：

- 选定 MVP 策略。
- 明确何时显示 busy/unsafe 提示。

### S3 - agent-im 复用/迁移研究

现有项目：

```text
/Users/xin/auto-skills/CtriXin-repo/agent-im
```

可参考：

```text
src/session-registry.ts
src/store.ts
src/ipc-server.ts
```

已有概念：

- session registry
- agent/model/provider/baseUrl/authToken metadata
- status transitions
- event stream
- permissions

验收：

- 哪些代码/概念可迁移。
- 哪些不应直接复制。
- mms-remote 的 local-first/E2EE/bridge 约束如何保持。

## 8. 最小范围能达到什么程度

### 8.1 最小 Read-only MVP

开发量：约 2-4 天。

能力：

- MMS 启动 Claude 时登记 session。
- iPhone 显示 `MMSChat` session list。
- iPhone detail 显示最近 output/transcript。
- 显示 cwd/model/provider/status/last activity。
- 支持 `Open on Mac`、`Copy resume command`、`Kill live process`。
- 不支持手机发送，或者只支持实验开关。

能达到：

```text
像 Codex Chat 的“会话状态页 / 只读观察页”
```

不能达到：

```text
手机聊天后 Claude 自动记忆
```

因为没有发送给 Claude。

### 8.2 最小 Writable MVP

开发量：约 4-7 天。

在 Read-only MVP 基础上新增：

- 手机输入发送到同一个 live Claude 进程。
- 如果进程 dead，可用 saved profile resume 后发送。
- MMSChat 缓存 pending user message。
- 输出轮询/stream 更新。

能达到：

```text
手机端能继续同一个 Claude session
Claude native session 理论上记录手机输入
关闭后 claude --resume 可恢复记忆
```

限制：

- Mac terminal 可能显示手机输入/输出，因为同一个进程在同一个 pane。
- 并发输入需要 MVP 级保护。
- transcript 结构化不如 Codex Chat 精准。

### 8.3 最小推荐范围

推荐先做：

```text
Read-only MVP + send spike behind feature flag
```

理由：

- 快速看到价值。
- 不和 Terminal 立即冲突。
- 可以先验证 transcript/source/model resume。
- send 是记忆闭环关键，但风险较高，适合 feature flag。

## 9. 并行 worktree 计划

适合并行，但必须拆开写范围。

### Worktree A - Bridge/backend

负责：

```text
P1 P2 P3 部分 P5
```

写范围：

```text
mms-remote-bridge/src/mmschat-*.js
mms-remote-bridge/test/mmschat-*.test.js
```

避免修改：

```text
CodexMobile/*
LocalizationManager.swift
project.pbxproj
```

### Worktree B - iOS UI/mock

负责：

```text
P4
```

写范围：

```text
CodexMobile/CodexMobile/Models/MMSChatModels.swift
CodexMobile/CodexMobile/Services/CodexService+MMSChat.swift
CodexMobile/CodexMobile/Views/MMSChat/*
```

避免修改：

```text
ContentView.swift
SettingsView.swift
LocalizationManager.swift
project.pbxproj
```

可以先用 mock data。

### Worktree C - Integration owner

负责：

```text
P0 P7
```

写范围：

```text
mms-remote-bridge/src/bridge.js
mms-remote-bridge/src/index.js
CodexMobile/CodexMobile/ContentView.swift
CodexMobile/CodexMobile/Services/LocalizationManager.swift
CodexMobile/CodexMobile.xcodeproj/project.pbxproj
```

职责：

- 协议冻结。
- 入口整合。
- 本地化。
- pbxproj file additions。
- 版本 bump。
- merge/review。

## 10. 冲突风险

### 10.1 低冲突文件

```text
mms-remote-bridge/src/mmschat-*.js
mms-remote-bridge/test/mmschat-*.test.js
CodexMobile/CodexMobile/Models/MMSChatModels.swift
CodexMobile/CodexMobile/Services/CodexService+MMSChat.swift
CodexMobile/CodexMobile/Views/MMSChat/*
```

### 10.2 中冲突文件

```text
mms-remote-bridge/src/bridge.js
mms-remote-bridge/src/index.js
mms-remote-bridge/bin/mms-remote.js
CodexMobile/CodexMobile/Views/SettingsView.swift
CodexMobile/CodexMobile/ContentView.swift
```

### 10.3 高冲突文件

```text
CodexMobile/CodexMobile/Services/LocalizationManager.swift
CodexMobile/CodexMobile.xcodeproj/project.pbxproj
CodexMobile/CodexMobile/Services/CodexService.swift
现有 Codex Chat timeline 核心 views
现有 Terminal core views
```

规则：

```text
LocalizationManager.swift / project.pbxproj 只能 integration owner 最后改。
不要让多个 worktree 同时改。
```

## 11. 安全和隐私边界

必须遵守：

- 不记录 live relay `sessionId`。
- 不记录 bearer-like pairing identifiers。
- 不把 provider key/token 写入 mmschat session store。
- store 中只保存 `authSecretRef` 或 `launchProfileName`。
- debug logs 可以记录 provider/model/profile name，但不能记录 token/base secret。
- E2EE 传输沿用现有 secure channel。

敏感字段禁止：

```text
authToken
ANTHROPIC_AUTH_TOKEN raw value
API key raw value
relay sessionId
pairing secret
```

## 12. 验证计划

### 12.1 Backend tests

建议命令：

```bash
cd mms-remote-bridge
npm test -- mmschat
```

或按现有 test runner 调整。

覆盖：

- register/list/update/hide。
- transcript cache。
- profile fingerprint。
- no-secret serialization。
- kill/hide/delete semantics。

### 12.2 CLI smoke

建议新增：

```bash
node ./bin/mms-remote.js mmschat smoke --json
```

验收：

- 创建 test Claude-like process 或 fake shell。
- 注册 session。
- list/detail 能读取。
- send 能进入 fake process。
- cleanup 不残留 tmux 垃圾。

### 12.3 iOS static validation

不主动跑 Xcode tests。

可做：

```bash
xcrun swiftc -parse ...
git diff --check
```

### 12.4 手工验证

Read-only MVP：

1. Mac 启动 bridge。
2. MMS 启动 Claude session。
3. iPhone 打开 MMSChat。
4. 能看到 session。
5. 点详情看到最新输出。
6. `Open on Mac` 打开同一 session。
7. `Kill live process` 后 native session 未删除。

Writable MVP：

1. iPhone 在 MMSChat 中发送一句唯一文本，例如 `phone_memory_probe_123`。
2. Claude response 出现。
3. kill live process。
4. 用 saved profile `claude --resume <id>`。
5. 询问刚才 probe。
6. Claude 能回忆或 transcript 显示该输入。

## 13. 未来进展路线

### Phase 1 - Read-only dashboard

目标：快速让 MMSChat 有价值。

能力：

- list sessions
- detail recent transcript
- status/provider/model/cwd
- open/copy resume/kill

### Phase 2 - Controlled send

目标：让手机输入进入 Claude native session。

能力：

- send to live Claude
- resume-and-send
- busy guard
- pending state

### Phase 3 - Better parser

目标：更像 Codex Chat。

能力：

- user/assistant/tool block separation
- Markdown/code block rendering
- cost/token/model extraction
- permission state extraction

### Phase 4 - Profile-aware resume

目标：不同 model/provider 更稳定。

能力：

- launch profile manager
- profile drift warning
- resume compatibility matrix
- model switch UI/indicator

### Phase 5 - Search/history

目标：长期可用。

能力：

- search sessions
- archive/hide
- project grouping
- cached preview
- timeline restore after bridge restart

## 14. 当前开放问题

1. Claude native transcript 的稳定读取方式是什么？
2. `claude --resume` 在不同 provider/model 下是否都可用？
3. MMSChat send 是否默认开启，还是 feature flag？
4. 同一 live Claude process 如果 Mac 和 iPhone 同时输入，MVP 怎么提示？
5. native session id 从哪里最可靠获取？
6. mmschat store 应放在 bridge device state 目录，还是独立 `~/.mms-remote/mmschat`？
7. UI 入口放在独立 tab、Codex sidebar 分组，还是 Terminal/Settings 中？

## 15. 审核建议

审核重点：

- 是否接受 “Claude native session 是唯一记忆真相”。
- 是否接受 MVP 先 read-only，再 feature flag send。
- 是否接受 MMSChat 不复刻完整 Codex timeline。
- 是否接受并行 worktree 三组拆分。
- 是否需要先做 S0/S1/S2 再写业务代码。

建议先执行：

```text
S0 transcript source research
S1 provider/model resume matrix
P0 protocol/data model finalization
```

然后再并行：

```text
P1 backend registry
P4 iOS mock UI
```

## 16. 文件位置和读取顺序

本文件位置：

```text
.ai/plan/mmschat-execution-plan.md
```

后续建议读取顺序：

```text
1. .ai/plan/mmschat-execution-plan.md
2. PLAN.md
3. AGENTS.md
4. CodexMobile/CodexMobile/Views/Terminal/TerminalHubView.swift
5. mms-remote-bridge/src/terminal-hub.js
6. /Users/xin/auto-skills/CtriXin-repo/agent-im/src/session-registry.ts
7. /Users/xin/auto-skills/CtriXin-repo/agent-im/src/store.ts
```
