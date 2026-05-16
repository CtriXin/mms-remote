# MMSChat Execution Plan v2

- Timestamp: 2026-05-16
- Status: ready-to-execute
- 基于 v1 审查后修正，解决了 6 个潜在坑点
- 单分支顺序执行，不使用并行 worktree

## 0. 决策记录

| 问题 | 决策 | 理由 |
|---|---|---|
| Source of truth | Claude native session | 避免双数据库不一致 |
| MVP 策略 | Read-only + send behind feature flag | 快速验证价值，send 风险高需要保护 |
| 并行 worktree | **不使用** | 单人开发，P0 是串行瓶颈，merge 冲突成本 > 并行收益 |
| UI 入口 | Terminal Tab 内 Segmented Control `Terminal │ Sessions` | 不增加第 4 个 Tab，场景重叠度高 |
| Transcript MVP 策略 | 取决于 S0 结论，fallback = raw terminal output | 不假装能做结构化解析 |

---

## 1. 核心原则

```
Claude native session = 记忆 source of truth
MMSChat = session index + status + transcript cache + Chat-like UI
Terminal = shell/PTY 控制面板，不和 MMSChat 混用 UI
```

---

## 2. S 任务（Spike / 调研）— 先做，不产出代码

### S0 - Claude transcript 源研究 (0.5天) — 🔴 最高优先级

**阻塞**: P3 的实现策略

```
S0-1. claude --help / claude --output-format 检查是否有 JSON/JSONL 结构化输出
S0-2. ls -la ~/.claude/ 检查目录结构，找 native session transcript 文件
      重点: ~/.claude/projects/<hash>/conversations/ 或类似路径
S0-3. 启动一个 Claude 会话，找到 nativeClaudeSessionId 的输出位置和格式
S0-4. tmux capture-pane -p 抓取真实 Claude 输出，评估可解析性
S0-5. 结论: transcript 来源优先级排序
      native file > json stream > tmux capture > 放弃结构化只展示 raw
S0-6. 结论: nativeClaudeSessionId 的最可靠获取方式
```

产物: `.ai/plan/progress/mmschat-s0-transcript-source.md`

### S1 - Provider/model resume 实测 (0.5天)

**阻塞**: P6

```
S1-1. create with kimi → resume with kimi
S1-2. create with kimi → resume with mimo
S1-3. create with mimo → resume with anthropic
S1-4. 记录成功/失败矩阵 + 错误信息
```

产物: `.ai/plan/progress/mmschat-s1-resume-matrix.md`

### S2 - Live input 安全策略 (0.5天)

**阻塞**: P5

```
S2-1. tmux send-keys 往运行中 Claude pane 发消息，记录行为
S2-2. Claude 正在 tool use / permission prompt 时 send-keys 的效果
S2-3. 设计 busy 检测策略（capture 最后 N 行检查 prompt pattern）
S2-4. 设计冲突提示文案（中英双语）
S2-5. 选定 MVP 策略（推荐: send-keys + busy guard）
```

产物: `.ai/plan/progress/mmschat-s2-input-safety.md`

### S3 - agent-im 迁移评估 (0.5天)

**阻塞**: P1

```
S3-1. 评估 agent-im/src/session-registry.ts 的可复用概念
S3-2. 评估 agent-im/src/store.ts 的 atomic write + fallback 模式
S3-3. 列出可迁移 vs 不应复制的部分
S3-4. 确认 mms-remote local-first/E2EE 约束如何保持
```

产物: `.ai/plan/progress/mmschat-s3-agent-im-reuse.md`

---

## 3. P 任务（开发任务）

### P0 - Protocol + Model 定稿 (1天)

**前置**: S0, S3

```
P0-1. 冻结 MMSChatSession JSON schema
P0-2. 冻结 RPC method names + params + response shapes
P0-3. 生成 CodexMobile/CodexMobile/Models/MMSChatModels.swift
P0-4. 生成 mms-remote-bridge/src/mmschat-protocol.js routing stub
P0-5. 定义 error codes (session_not_found / pane_dead / busy / resume_failed)
P0-6. 冻结删除语义 (hide vs kill vs destroy)
```

写范围:
```
.ai/plan/mmschat-protocol-spec.md
mms-remote-bridge/src/mmschat-protocol.js
CodexMobile/CodexMobile/Models/MMSChatModels.swift
```

#### MMSChatSession 数据模型

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
  "hidden": false
}
```

禁止存储: authToken 明文 / API key / relay sessionId / pairing secret

#### RPC 方法

```
mmschat/list          — 列出 sessions
mmschat/detail        — session 详情 + transcript
mmschat/attach        — 绑定/观察 live session
mmschat/send          — 发送消息到 Claude (feature flag)
mmschat/resume        — 恢复 dead session
mmschat/openVisible   — 在 Mac 打开对应 terminal
mmschat/kill          — 停止 live 进程 (不删 native session)
mmschat/hide          — 从列表隐藏
mmschat/cache/clear   — 清除 transcript 缓存
```

### P1 - Bridge registry + store (1.5天)

**前置**: P0

```
P1-1. 创建 mmschat-store.js (atomic write + corrupt fallback)
P1-2. 创建 mmschat-registry.js (register/update/list/hide/clear-cache)
P1-3. status transitions: running → idle → dead → needs-resume
P1-4. lastActivity / preview 自动更新
P1-5. 确保 store 不被 reset-pairing 清掉
P1-6. Node tests 覆盖核心 CRUD
```

写范围:
```
mms-remote-bridge/src/mmschat-store.js
mms-remote-bridge/src/mmschat-registry.js
mms-remote-bridge/test/mmschat-registry.test.js
mms-remote-bridge/test/mmschat-store.test.js
```

### P2 - Claude launcher 集成 (1天)

**前置**: P1

```
P2-1. 选定 session 发现机制:
      方案 A: MMS claude wrapper 脚本加 IPC 通知 (推荐)
      方案 B: 定期扫描 tmux pane currentCommand
P2-2. 实现自动注册逻辑
P2-3. 从启动信息提取 provider/model/cwd/nativeSessionId
P2-4. 处理 nativeSessionId pending 状态
P2-5. 不影响现有 terminal/create
```

写范围:
```
mms-remote-bridge/src/mmschat-launcher.js
mms-remote-bridge/bin/mms-remote.js (或现有 launcher entry)
```

### P3 - Transcript 观测 (1.5-5天，取决于 S0)

**前置**: P1, S0

```
如果 S0 结论 = native transcript 文件可用:
  P3-1. 读取 ~/.claude/.../conversations/ 文件
  P3-2. 解析 JSON 格式为 message blocks
  P3-3. 缓存到 mmschat transcript-cache
  工作量: 1.5 天

如果 S0 结论 = 只有 tmux capture:
  P3-1. tmux capture-pane 获取 raw text
  P3-2. 基础 ANSI strip（复用 terminal-hub 已有逻辑）
  P3-3. 不做 user/assistant 分块，直接展示 raw output
  P3-4. preview = 最后 3 行非空文本
  工作量: 1.5 天（放弃结构化）

如果 S0 结论 = 有 JSON stream 模式:
  P3-1. 用 --output-format json 启动 Claude
  P3-2. 解析 JSONL stream 为 message blocks
  P3-3. 缓存 + 增量更新
  工作量: 2 天
```

写范围:
```
mms-remote-bridge/src/mmschat-transcript.js
mms-remote-bridge/src/mmschat-parser.js (如果需要)
mms-remote-bridge/test/mmschat-transcript.test.js
```

### P4 - iOS MMSChat list/detail UI (2天)

**前置**: P0

```
P4-1. MMSChatModels.swift (从 P0 复制)
P4-2. CodexService+MMSChat.swift (RPC 调用层)
P4-3. MMSChatListView.swift (session 列表，按 project/cwd 分组)
P4-4. MMSChatDetailView.swift (transcript 详情，monospace text)
P4-5. 空态 / 错误态 / 加载态
P4-6. 本地化 (zh-Hans + en)
P4-7. Terminal Tab 内 Segmented Control 切换入口
```

写范围:
```
CodexMobile/CodexMobile/Models/MMSChatModels.swift
CodexMobile/CodexMobile/Services/CodexService+MMSChat.swift
CodexMobile/CodexMobile/Views/MMSChat/MMSChatListView.swift
CodexMobile/CodexMobile/Views/MMSChat/MMSChatDetailView.swift
```

不修改:
```
现有 Codex Chat timeline 核心 views
现有 Terminal 核心 views (只加 segmented control 入口)
```

### P5 - Action integration (2天)

**前置**: P3, S2

```
P5-1. Open on Mac (复用 terminal/openVisible 逻辑)
P5-2. Copy resume command
P5-3. Kill live process (不删 native session)
P5-4. Send message (behind feature flag, 默认关闭)
      - busy guard: capture 最后一行检查 prompt
      - 冲突提示文案
P5-5. Resume dead session (用 saved profile)
```

写范围:
```
mms-remote-bridge/src/mmschat-hub.js
CodexMobile/CodexMobile/Services/CodexService+MMSChat.swift (追加)
CodexMobile/CodexMobile/Views/MMSChat/* (追加 action buttons)
```

### P6 - Provider/model profile (1天)

**前置**: S1

```
P6-1. 保存 launch profile name/fingerprint
P6-2. secret 只存 ref
P6-3. resume 时恢复 env
P6-4. UI 显示 last known vs current live model/provider
```

写范围:
```
mms-remote-bridge/src/mmschat-profile.js
mms-remote-bridge/test/mmschat-profile.test.js
```

### P7 - Integration + release polish (1.5天)

**前置**: P1-P6 全部完成

```
P7-1. bridge.js handleApplicationMessage 加 mmschat routing
P7-2. Terminal Tab segmented control 集成
P7-3. LocalizationManager.swift 新增所有 key
P7-4. project.pbxproj 新增文件
P7-5. 版本 bump
P7-6. 全链路手工验证
```

写范围 (高冲突，最后统一改):
```
mms-remote-bridge/src/bridge.js
CodexMobile/CodexMobile/ContentView.swift
CodexMobile/CodexMobile/Services/LocalizationManager.swift
CodexMobile/CodexMobile.xcodeproj/project.pbxproj
```

---

## 4. T 任务（测试）

| ID | 名称 | 类型 | 对应 | 工作量 |
|---|---|---|---|---|
| T0 | JSON schema 冻结验证 | Manual | P0 | 0.25天 |
| T1 | Registry CRUD + corrupt fallback | Node test | P1 | 0.5天 |
| T2 | Launcher 登记 + session 发现 | Node + Manual | P2 | 0.5天 |
| T3 | Transcript 准确度 | Node + Fixture | P3 | 0.5天 |
| T4 | iOS mock 渲染 | Preview / 手工 | P4 | 0.5天 |
| T5 | Send/Kill/Resume E2E | Manual | P5 | 0.5天 |
| T6 | Resume 兼容矩阵 | Manual | P6 | 0.25天 |
| T7 | 全链路 MVP 走通 | Manual E2E | P7 | 0.5天 |

### T7 E2E 验证脚本

```
1. Mac: npm start (bridge)
2. Mac: mms claude --model kimi ... (启动 Claude)
3. iPhone: 打开 Terminal Tab → 切到 Sessions → 看到新 session
4. iPhone: 点详情 → 看到最近输出
5. iPhone: Open on Mac → Mac terminal 打开对应 pane
6. iPhone: Kill → 进程停止、session 变 needs-resume
7. iPhone: Resume → 进程恢复
8. 关闭 bridge → 重启 → session 索引持久化
```

---

## 5. 执行顺序（单分支 sequential）

```
Phase 0: Spike (1天)
  S0 + S3 并行 → 产出结论文档

Phase 1: 定稿 (1天)
  P0 → T0
  (S1, S2 可在此阶段空闲时穿插做)

Phase 2: Bridge 核心 (2.5天)
  P1 → T1 → P2 → T2

Phase 3: iOS UI + Transcript 并行推进 (2天)
  P4 → T4 (先用 mock data)
  P3 → T3 (取决于 S0 结论)

Phase 4: Action + Profile (2天)
  P5 → T5
  P6 → T6

Phase 5: 收尾 (1.5天)
  P7 → T7

总计: ~10 工作日 (含测试)
Read-only MVP 最快路径: Phase 0-3 = ~6.5 天
```

---

## 6. 删除语义

```
Hide:     mmschat index hidden=true, 不删 native session, 不杀进程
Kill:     杀 tmux pane/process, 不删 native session, 保留 mmschat index
Destroy:  杀进程 + 删 mmschat cache, 不删 native session (默认)
          可选: 删 native session (高级危险操作, 二次确认)
```

---

## 7. 安全边界

- 不记录 relay sessionId
- 不记录 bearer-like pairing identifiers
- store 中不存 provider key/token 明文，只存 authSecretRef
- debug logs 可记录 provider/model/profile name
- E2EE 沿用现有 secure channel

---

## 8. 不做的事（减法）

| 不做 | 理由 |
|---|---|
| 独立第 4 个 Tab | 3 Tab 是移动端合理上限 |
| 双数据库同步 | 不一致风险 |
| 非 Claude agent transcript 解析 | MVP 只做 Claude |
| Markdown 渲染 | Phase 3+ 的事 |
| transcript 自动刷新 < 1s | 太贵，MVP 用 pull-to-refresh + 5s polling |
| 多 worktree 并行 | 单人开发 merge 成本 > 收益 |

---

## 9. 开放问题（带入 S0 解决）

1. Claude native transcript 的稳定读取方式？→ S0
2. nativeClaudeSessionId 从哪里最可靠获取？→ S0
3. claude --resume 在不同 provider/model 下是否可用？→ S1
4. 同时输入冲突的 MVP 提示策略？→ S2
5. mmschat store 放在哪个目录？→ P0 定稿时决定
