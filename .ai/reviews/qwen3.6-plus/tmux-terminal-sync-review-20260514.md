# tmux-terminal-sync Review - Tmux Terminal Sync & Multi-Backend

- Date: 2026-05-14
- Reviewer: qwen3.6-plus
- CLI: claude-code
- Started: 2026-05-14
- Completed: 2026-05-14
- Duration: <1m

## Overall Verdict
BLOCKED

## Blocking Findings

**BLOCK-1: Milestone implementation not committed**

Pack claims: "Add tmux transport to bridge, enabling phone to view/control all Mac terminal windows bidirectionally. Relay multi-client support. iOS terminal renderer."

Commit `6e1f7a0` (Initial commit) contains exactly one file: `LICENSE` (Apache-2.0, 201 lines).

No tmux transport, no bridge changes, no relay modifications, no iOS terminal renderer, no Codex mode logic exists anywhere in the committed tree.

Working tree contains full iOS app (`CodexMobile/`), bridge (`mms-remote-bridge/`), relay (`relay/`) — all untracked. None of these contain tmux-related code (verified via `find -name '*tmux*'` and `grep -rl 'tmux'` across all source files — zero hits outside review pack artifacts).

The pack's `changed_files: ["LICENSE"]` is technically correct for the commit but contradicts the summary/description. Pack status `ready_for_review` is false — there is no implementation to review.

**Resolution required:**
1. Point the pack at a commit that actually contains tmux-terminal-sync implementation, or
2. Commit the implementation code and update the pack's commit hash.

## Non-Blocking Findings

- `AGENTS.md` listed as `read_only_files` but is untracked — harmless for inspection but not part of the commit boundary.
- Prior reviewers (mimo-v2.5, K2.6) independently reached the same BLOCKED verdict for identical reasons.

## Boundary Check

- No out-of-scope files changed: yes (only LICENSE committed)
- No forbidden external actions: yes
- Validation evidence reviewed: N/A — pack validation section says "not recorded", no feature code exists

## Plan Review (PLAN.md assessment)

> 注：commit 未包含实现代码，但 PLAN.md 存在于工作树中。以下是对 plan 本身的独立评估。

### Plan Verdict: PASS_WITH_NOTES

架构方向可信，核心链路可支撑用户核心需求："手机看所有 Mac 终端窗口，开新终端，双端同步"。

### 可行性评估

现有架构已提供关键基础设施，plan 利用正确：

1. **Transport 抽象已存在** — `codex-transport.js` 接口 (`send/onMessage/onClose/onError/onStarted/shutdown/describe`) 清晰。`tmux-transport.js` 实现同一接口是正确做法。
2. **Relay 广播已接近就绪** — `relay.js:163-169` 已遍历 `session.clients` 做 Mac→所有 client 广播。只需改 `relay.js:132-148` 的"踢掉旧 mobile client"逻辑。plan 估算 ~10 行改动准确。
3. **E2EE 完全复用** — `secure-transport.js` 不动，正确。
4. **bridge.js 消息路由清晰** — `handleApplicationMessage()` 链式 dispatch（L522-572），加 tmux case 自然。

### 需求匹配

| 需求 | 可行性 |
|------|--------|
| 手机看所有 Mac 终端窗口 | 可 — `tmux list-sessions` 自动发现 (Phase 5) |
| 开新终端 | 可 — `tmux new-session -d -s <name> -c <cwd>` |
| 终端内容双端同步 | 可 — node-pty data event + relay 广播 |
| Mac/手机互不干扰 | 可 — tmux 天然多 attach 客户端 |
| 保留 Codex 模式 | 可 — transport select 模式，不动现有代码 |

### Blocking 风险

无。

### 非阻塞风险

**RISK-1: iOS 终端渲染方案过于简化 [中风险]**

Plan 用 `ScrollView + ForEach(Text) + AttributedString`。v1 够用但有隐患：

- **ANSI 控制码**：plan 说 v1 `strip-ansi` 只留纯文本。`strip-ansi` 只 strip 颜色转义，不处理 `\r`（回车行覆盖）、`\b`（退格）、`\033[H`（光标定位）。`wget`/`npm install` 进度条会变成 100 行垃圾输出。
- **性能**：`ForEach(outputLines)` 在 5000 行时 SwiftUI 明显卡顿。终端场景 5000 行几分钟就满。
- **建议**：完整内容拼接后单次 `Text` 渲染，或用 `LazyVStack`。`\r` 行覆盖做合并处理。

**RISK-2: node-pty 原生编译依赖 [低风险]**

Plan 提到 fallback 到 `child_process + tmux capture-pane polling`，但没写 fallback 实现。`node-pty` 在 macOS arm64 + Node 22+ 偶有编译问题。

**建议**：Phase 2 验收标准加入 "fallback polling 路径可用"。

**RISK-3: tmux capture-pane 是全量快照，非增量 [中风险]**

Plan 说 `capture-pane` 100ms polling 做断线恢复兜底。但正常路径 node-pty 断掉后，fallback 用 `capture-pane -p` 拿整个 pane 缓冲区（默认 2000 行），每次 100ms 全量拉，relay 会撑爆。

**建议**：capture-pane polling 用 scrollback cursor 做增量 diff，或只在 attach 瞬间全量拉一次。

### Plan 遗漏项

1. **ANSI 输出流控** — tmux pane 高速输出（如 `cat /var/log/system.log`）时，bridge→relay WebSocket 消息频率未定义。建议加节流（50ms 批量合并）。
2. **多 pane 并发** — Phase 3 单 session attach，Phase 5 说"看到所有 tmux session 列表"但没说能否同时 attach 多个。建议明确：Phase 3 单 session，Phase 5 多 session tab 切换。
3. **tmux session 名冲突** — 手机创建新 session 时名字已存在，plan 没处理。建议加 name collision 策略。

### Plan 可信度

| 维度 | 评分 |
|------|------|
| 架构方向 | 9/10 — transport 抽象 + relay 广播，正确 |
| 改动量估算 | 8/10 — 行数和阶段合理，略乐观 |
| 风险识别 | 7/10 — 漏了 ANSI 控制码、输出流控、capture-pane 增量 |
| 实现路径 | 8/10 — 分阶段正确，Codex 并存合理 |

结论：plan 架构扎实，方向正确。上述 3 个非阻塞风险建议在 Phase 2 实现阶段解决。可以开始实施。
