# MMS Remote V2 — 升级路线图

- Timestamp: 2026-05-16
- Status: approved-for-execution
- 基于: 全量代码审计 + 竞品验证 + 用户确认
- 前置文档: `mmschat-execution-plan-v2.md`（MMSChat 详细任务已有，本文档补充全局方向和 MMS 集成）

## 0. 执行 Agent 须知

本文档是 V2 的全局路线图。MMSChat 的详细 P/S/T 任务已在 `mmschat-execution-plan-v2.md` 中定义，不重复。
本文档新增的是：
1. V1→V2 的完成度差异
2. 竞品定位和差异化结论
3. MMS Model Router 集成（新方向，mmschat plan 未覆盖）
4. Terminal 产品化收尾
5. 全局分阶段路线和版本规划

读取顺序：
1. `AGENTS.md`
2. `.ai/plan/current.md`
3. **本文档** `.ai/plan/v2-roadmap.md`
4. `.ai/plan/mmschat-execution-plan-v2.md`（MMSChat 详细任务）
5. `Docs/terminal_health_check.md`（Terminal 技术债项）

---

## 1. V1 → V2 完成度对照

| 能力 | V1 状态 | V2 目标 |
|------|---------|---------|
| E2EE iPhone ↔ Mac 配对 | ✅ 成熟 | 保持 |
| Codex Chat 远程控制 | ✅ 成熟 | 保持，降级为"众多 Agent 之一" |
| Git 操作 (11 RPC) | ✅ 成熟 | 保持 |
| Terminal Hub (tmux) | ✅ MVP | → Stable renderer 先产品化，SwiftTerm 修复双字符后再恢复候选 |
| Terminal Stream | 🟡 实验 | → 稳定化 + 断线重连；当前 SwiftTerm live renderer 因 iOS 输入双字符暂停默认 |
| 后台 Daemon (macOS) | ✅ 成熟 | 保持 |
| npm v1.5.0 | ✅ 已发 | → v2.x |
| **MMS config 集成** | 🔴 零 | → Bridge 读 MMS config，iOS Model Picker |
| **隔离启动 (overlay)** | 🔴 零 | → 每次启动独立 config dir |
| **多模型切换 (ccswitch)** | 🔴 零 | → 运行时换模型 |
| **MMSChat 会话层** | 🔴 仅 Plan | → 执行 mmschat-execution-plan-v2.md |
| **SwiftTerm 默认渲染** | 🔴 gate 中 | → 验收后设为默认 |

---

## 2. 竞品定位结论

### 2.1 官方产品的锁定

| 产品 | 认证 | 模型支持 | 锁定 |
|------|------|----------|------|
| Claude Remote Control | OAuth 订阅 (Pro/Max only) | 仅 Claude | 🔴 完全锁死，不支持 API Key |
| Codex Mobile (ChatGPT App) | OpenAI 账号登录 | 主要 OpenAI 模型 | 🟡 半锁 |
| **MMS Remote** | **API Key + 自定义 URL** | **任意 Provider/Model** | 🟢 完全开放 |

### 2.2 其他竞品

| 产品 | 定位 | 与我们的关系 |
|------|------|-------------|
| Moshi (getmoshi.app) | iOS AI Agent 专用终端，Mosh 协议 | 终端体验更专业，但无 Model Router |
| LinkShell | 开源 WebSocket PTY 桥，架构最相似 | 无隔离启动，无会话管理 |
| Cosyra | 云托管 AI Terminal，$20-30/月 | 不同赛道 (云 vs 本地) |
| AgentsRoom | Multi-Agent 可视化编排 | 代表未来方向，但闭源 |

### 2.3 差异化结论

MMS Remote V2 的护城河 = **MMS 作为 Model Router**：
- 官方产品只控制自家 Agent → 我们跨生态
- 官方产品要求 OAuth/登录 → 我们 API Key 即用 (BYOK)
- 官方产品无隔离启动 → 我们 overlay 隔离 config
- 官方产品无法切模型 → 我们 ccswitch 运行时切换
- 竞品无会话索引 → 我们有 MMSChat session registry

**V2 定位 = 任意 AI Agent 的唯一 Provider-agnostic 移动中控台。**

---

## 3. V2 四大方向

### 方向 A：MMS Model Router 集成（核心护城河，mmschat plan 未覆盖）

把 MMS launcher 的 Provider/Model/Preset/Overlay 能力接入 bridge + iOS。

MMS 已有能力（mms-remote 利用度 = 零）：

| MMS 能力 | 对应代码 |
|----------|----------|
| 多 Provider 定义 `[[providers]]` | `~/.config/mms/config.toml` |
| API Key + base_url 配置 | `credentials.sh` |
| Overlay 隔离启动 | `mms_launcher_profile.py` / `overlays/*.toml` |
| Preset 模型组合 `[presets.*]` | `config.toml` |
| ccswitch CLI 切换 | `mms_core.py` |
| 会话索引 + 使用统计 | `mms_session_index.py` / `mms_usage.py` |

#### A 系列任务

| ID | 内容 | 工作量 | 前置 | 优先级 |
|----|------|--------|------|--------|
| A1 | Bridge 读取 MMS config：解析 `~/.config/mms/config.toml` 的 providers/presets/credentials（只读 metadata，不传 key 到 iOS） | 2天 | 无 | **P0** |
| A2 | iOS Model Picker：展示可用 Provider + Model 列表，选择后通过 bridge 创建对应隔离 pane | 3天 | A1 | **P0** |
| A3 | 隔离启动：创建 pane 时复用 MMS overlay 机制（`_prepare_isolated_config_dir` 逻辑移植到 JS 或调用 Python） | 2天 | A1 | **P0** |
| A4 | 运行时切模型：pane 运行中换模型（Claude = ccswitch，其他 = 重启 pane 用新 config） | 3天 | A3 | **P1** |
| A5 | Provider 健康态：bridge 定期探测 Provider 可用性，iOS 显示 🟢/🔴 | 2天 | A1 | **P1** |
| A6 | Preset Quick Launch：一键启动预设组合（coding/cheap/codex-gpt） | 1天 | A2 | **P1** |
| A7 | 使用统计同步：token/cost 数据同步到 iOS 展示 | 2天 | A1 | **P2** |

#### A 系列新增 Bridge 文件

```
mms-remote-bridge/src/mms-config-reader.js   — 解析 ~/.config/mms/config.toml
mms-remote-bridge/src/agent-launcher.js       — 基于 MMS config 创建隔离 tmux pane
mms-remote-bridge/src/provider-health.js      — Provider 可用性探测
mms-remote-bridge/test/mms-config-reader.test.js
mms-remote-bridge/test/agent-launcher.test.js
```

#### A 系列新增 iOS 文件

```
CodexMobile/CodexMobile/Models/MMSConfigModels.swift
CodexMobile/CodexMobile/Views/AgentLauncher/AgentLauncherView.swift
CodexMobile/CodexMobile/Services/CodexService+AgentLauncher.swift
```

#### A 系列新增 RPC

```
mms/providers       → 获取可用 Provider 列表（id/name/protocols/health，不含 key）
mms/presets         → 获取 Preset 列表
mms/models          → 获取指定 Provider 的可用模型
mms/health          → 获取 Provider 健康状态
mms/launch          → 基于 provider+model+cwd 创建隔离 Agent pane
mms/switch-model    → 运行中切换模型
mms/usage           → 获取使用统计
```

#### A 系列安全规则

- Provider API Key / token 不得通过 RPC 传到 iOS 端
- iOS 只看到 provider name + health status + model list
- Credentials 在 bridge 端解析，用于启动进程的 env，不序列化
- `mms/launch` 的 credential 引用走 bridge 本地的 MMS config，不从 iOS 端接收

#### A1 实现指引

Bridge 需要一个 TOML 解析器。选项：
- A. `npm install smol-toml`（零依赖，纯 JS TOML parser）
- B. 调用 Python：`python3 -c "import tomllib; ..."` 一次性读取
- 推荐 A（保持 Node 纯 JS 风格，与现有依赖风格一致）

读取路径优先级：
1. `$MMS_CONFIG_DIR/config.toml`
2. `$XDG_CONFIG_HOME/mms/config.toml`
3. `~/.config/mms/config.toml`

#### A3 隔离启动实现指引

两种方案：
- A. Bridge 自己在 JS 端复现 `_prepare_isolated_config_dir` 逻辑（copy config files → tempdir → set env）
- B. Bridge 调用 `python3 -m mms_launcher_profile --profile <name> --json` 获取隔离 dir

推荐 A（减少对 Python 进程的运行时依赖，MMS 可能不在 PATH）。
核心逻辑：
```
1. 复制 config.toml + credentials.sh + override.toml 到 tempdir
2. 应用 overlay（merge provider_overrides / visible_clis / visible_providers）
3. 设置 tmux pane env: MMS_CONFIG_DIR=<tempdir>
4. 启动命令: mms claude --model <model> 或 mms codex --model <model>
```

---

### 方向 B：Terminal 产品化收尾

详细技术债项见 `Docs/terminal_health_check.md`。

| ID | 内容 | 工作量 | 优先级 |
|----|------|--------|--------|
| B1 | SwiftTerm 渲染器验收 → 设为默认（验收条件：stream replay、中文输入法、Enter/空格、光标、ANSI 色彩、resize、无横向溢出、无乱码、无输入双字符）。当前用户复现输入后双字符/影子，必须先修；默认回 Stable。 | 3天 | **P0** |
| B2 | Stream 断线自动重连 | 1天 | **P0** |
| B3 | 技术债清理：合并 3 处 paneMatches → `ManagedTerminalPane.matches()` extension；提取 TerminalTextUtilities；统一 Pane ID 为 canonicalId；拆分 SwiftTerminalHubView | 3天 | **P0** |
| B4 | 快捷键升级：Sticky modifier + F1-F12 + Alt + 外接键盘检测 | 3天 | **P1** |
| B5 | Terminal 新建会话 UX：点击 `+` 先打开创建 sheet；可浏览选择 Mac folder/cwd；每次创建可单独选择是否打开 Mac 端可见终端和目标 app，不只依赖全局设置 | 2天 | **P1** |
| B6 | 终端主题可选 | 2天 | **P2** |
| B7 | 删除 legacy TerminalHubView.swift（需用户明确同意后执行） | 0.5天 | **P2** |

---

### 方向 C：MMSChat 会话层

**完整任务定义已在 `mmschat-execution-plan-v2.md`，不重复。**

执行 agent 直接读那个文件。关键依赖提示：

| mmschat 任务 | 与 A 系列的关系 |
|-------------|----------------|
| P2 (Claude launcher 集成) | 应复用 A3 的隔离启动机制，不要重复实现 |
| P6 (Provider/model profile) | 应复用 A1 的 MMS config reader，不要独立解析 |
| S0 (Transcript 源调研) | 不依赖 A 系列，可立即执行 |
| S1 (Resume 实测) | 不依赖 A 系列，可立即执行 |

---

### 方向 D：平台与基础设施

| ID | 内容 | 工作量 | 优先级 |
|----|------|--------|--------|
| D1 | Relay failover：多 relay 测速 + 断线自动切换 | 3天 | **P1** |
| D2 | macOS Menu Bar companion：Agent 状态速览 | 3天 | **P2** |
| D3 | Apple Watch / Widget / Live Activities | 3天 | **P3** |

### 方向 E：Upstream Remodex Watchlist（只借鉴，不整合主线）

Source checked: upstream Remodex `origin/main` = `603dfc5` on 2026-05-17 local time. License remains Apache-2.0. Treat upstream as an idea/reference source; do not direct-merge large branches into MMS Remote because our product direction is now Mac-local Bridge/tmux/SwiftTerm plus MMS Model Router.

| ID | 内容 | 工作量 | 优先级 |
|----|------|--------|--------|
| E0 | Open-source hygiene：保留 Apache-2.0 `LICENSE`、保留 `NOTICE` attribution、检查 cherry-pick 引入的第三方 license；不要把 private relay/default domains 写入公开源码或 docs | 0.5天/每次 release | **P0** |
| E1 | iPad support：手工 port `codex/ipad-os` 的 presentation 思路；不要直接复制 `RemodexPad` target。优先把现有 `MMS Remote` app target 从 iPhone-only 调整为 iPhone+iPad，再适配 QR/camera/sheets/composer/diff/Terminal 布局 | 3-5天 | **P1** |
| E2 | iOS foreground WebSocket keepalive：参考 upstream `f5ac30f`/PR foreground keepalive，给 Network.framework WebSocket 增加 foreground ping loop、停止/重启 lifecycle、连接失败 recovery tests | 1-2天 | **P1** |
| E3 | Composer draft persistence：参考 upstream `3ece820` 的 unsent per-thread draft persistence；本地加密/落盘保存输入、mentions、attachments，切 thread / app restart 后恢复 | 2-3天 | **P1** |
| E4 | My Macs / multi-Mac UX：参考 `dpcode/multiple-macos` 的 `MyMacsView`、Mac-scoped local state、显式 switch/forget/recovery；必须适配现有 E2EE trusted Mac registry 和 relay resolve，不整条 merge | 4-6天 | **P2** |
| E5 | Relay subpath self-host：参考 upstream `/relay/v1/...` HTTP API prefix support，支持 reverse proxy 挂在 `/relay` 或自定义 prefix；同时更新 tests 和 URL builder | 1天 | **P2** |
| E6 | Timeline / markdown performance：跟踪 upstream `d4cd146` streaming smoothness 和 `603dfc5` RemodexTextKit migration；只有在本地 Textual/AttributedString cache 仍卡顿时再手工 port | 2-4天 | **P2** |
| E7 | Terminal SSH ideas only：不要引入 upstream direct SSH/GhosttyKit/Citadel stack。只可摘 keybar、host platform modifier mapping、profile nickname、known-host reset UX 等局部交互 | 1-2天 | **P3** |
| E8 | Upstream contribution posture：暂不投入大 PR。Remodex `CONTRIBUTING.md` 明确 not actively accepting contributions；如未来贡献，只做 tiny bugfix/docs/reliability patch，并先开 issue/RFC 探口风 | 0.5天 | **P3** |

Terminal SSH decision:
- upstream direction = iPhone native SSH client + `GhosttyKit.xcframework` + phone-side private key/known-host/profile storage.
- MMS Remote direction = iPhone controls Mac-local Bridge/tmux/SwiftTerm panes, credentials stay on Mac, Terminal is tied to Codex/MMS local runtime.
- Therefore direct SSH overlaps conceptually but conflicts architecturally. Importing the full stack would add binary/vendor surface, mobile SSH key risk, and a second terminal protocol. Do not do this unless the product explicitly decides to add a separate "direct SSH client" mode.

Open-source / contribution decision:
- Continue developing MMS Remote independently under Apache-2.0 with preserved `LICENSE` and `NOTICE` attribution.
- Rename/branding/package/bundle-id changes are allowed under Apache-2.0; do not imply upstream endorsement or use Remodex marks for our fork.
- Do not spend engineering cycles preparing a large upstream tmux Terminal PR now. Their contribution policy and product direction make acceptance unlikely.
- If relationship-building is desired later, open a small issue/discussion first; only send tiny focused patches that remove MMS/private-relay/product-specific code.

#### Public release / review guard

- 公开版、GitHub source checkout、App review/demo build 不得内置用户私有公网 relay。
- 用户自己的两个公网 relay 只允许进入 private package defaults / 私有配置 / 本机 daemon config，不进公开源码、README 示例真实域名、review artifact、截图或默认 QR。
- Release checklist 必须检查：`private-defaults.json` 未进 repo；`MMS_REMOTE_PACKAGE_DEFAULT_RELAY_URL(S)` 只在私有发布流水线注入；source checkout 默认仍为空或 local/self-host。
- iOS pairing UX 可支持多 relay failover，但公开版默认必须让用户 self-host / 自填 / 包发行方自行配置，不能让陌生用户消耗用户私人服务器。

---

## 4. 全局执行顺序

```
Phase 0: Spike + Terminal 收尾 (并行，1 周)
  ├── S0 + S1 + S2 + S3 (mmschat spikes)
  ├── B1 SwiftTerm 验收 → 默认
  ├── B2 Stream 自动重连
  └── B3 技术债清理

Phase 1: MMS 集成 + MMSChat 基础 (并行，1.5 周)
  ├── A1 Bridge 读 MMS config
  ├── A2 iOS Model Picker
  ├── A3 隔离启动
  ├── P0 MMSChat protocol 定稿 (复用 A1)
  └── P1 MMSChat bridge registry

Phase 2: 功能闭环 (1.5 周)
  ├── A4 运行时切模型
  ├── A5 Provider 健康态
  ├── A6 Preset Quick Launch
  ├── P2 MMSChat launcher 集成 (复用 A3)
  ├── P3 Transcript 观测
  └── P4 iOS MMSChat UI

Phase 3: Action + Profile (1 周)
  ├── P5 MMSChat send/resume/kill
  ├── P6 MMSChat provider/model profile (复用 A1)
  ├── B4 快捷键升级
  └── D1 Relay failover

Phase 4: 收尾 (0.5 周)
  ├── P7 MMSChat integration + release
  ├── A7 使用统计同步
  └── 版本 bump → 2.0.0
```

---

## 5. 版本规划

| 版本 | 里程碑 | 核心交付 |
|------|--------|----------|
| **2.0.0** | Terminal 产品化 + MMS 基础集成 | SwiftTerm 默认 + Stream 重连 + 技术债清零 + Bridge 读 MMS config + iOS Model Picker + 隔离启动 |
| **2.1.0** | MMSChat MVP | Session Registry + 会话列表/详情 + send/resume/kill |
| **2.2.0** | 体验增强 | 运行时切模型 + Provider 健康 + Preset Quick Launch + Relay failover |
| **2.3.0** | 平台扩展 | 使用统计 + Menu Bar + Watch/Widget |

---

## 6. 架构图

```
V2 架构:

iPhone ──── Relay ──── Bridge ──┬── MMS Config Reader (新增 A1)
                                │     ├── providers[] 解析
                                │     ├── presets[] 解析
                                │     └── credentials 解析 (不传到 iOS)
                                │
                                ├── Agent Launcher (新增 A3)
                                │     ├── MMS overlay 隔离启动
                                │     ├── model 切换 (ccswitch)
                                │     └── Provider 健康探测
                                │
                                ├── MMSChat Hub (新增 C 系列)
                                │     ├── session registry/store
                                │     ├── transcript observer
                                │     └── send/resume/kill actions
                                │
                                ├── Terminal Hub (tmux - 现有)
                                ├── Codex Transport (现有)
                                └── Git Handler (现有)
```

---

## 7. 安全边界

- Provider API Key 不得通过 RPC 传到 iOS 端
- iOS 只看到 provider name / model list / health status
- MMSChat store 不存 auth token 明文，只存 authSecretRef
- 不记录 relay sessionId / pairing identifiers
- E2EE 沿用现有 secure channel
- 隔离 config tempdir 用 atexit cleanup

---

## 8. 开放决策（执行 agent 遇到时需要确认）

| 决策点 | 推荐 | 备选 |
|--------|------|------|
| TOML 解析方案 | npm `smol-toml` (纯 JS) | 调用 Python `tomllib` |
| MMS config 读取方式 | Bridge 直接读文件 | 通过 MMS Python IPC |
| 隔离 config 创建 | Bridge JS 端复现逻辑 | 调用 Python `mms_launcher_profile` |
| ccswitch 机制 | Bridge 调用 `mms ccswitch` CLI | Bridge 自己实现 env 替换 |
| MMSChat UI 入口 | Terminal Tab 内 Segmented Control | 独立 Tab（不推荐） |
| Provider health 探测频率 | 每 60s 被动 + 手动刷新 | 每 10s 主动轮询 |

---

## 9. 与已有 plan 的关系

```
v2-roadmap.md (本文档)
  ├── 全局方向 + 竞品 + 版本规划
  ├── A 系列任务 (MMS 集成，新增)
  ├── B 系列任务 (Terminal 收尾，引用 terminal_health_check.md)
  ├── D 系列任务 (平台扩展，新增)
  └── C 系列 = 指向 mmschat-execution-plan-v2.md

mmschat-execution-plan-v2.md (已有)
  ├── S0-S3 spike 任务
  ├── P0-P7 开发任务
  └── T0-T7 测试任务

terminal_health_check.md (已有)
  └── 技术债详细项 + 拆分建议

current.md (已有)
  └── 当前稳定点 + 下一步
```
