# tmux-terminal-sync Review - Tmux Terminal Sync & Multi-Backend

- Date: 2026-05-14
- Reviewer: deepseek-v4-flash
- CLI: claude-code
- Started: 2026-05-14T15:30:00+00:00
- Completed: 2026-05-14T15:32:00+00:00
- Duration: ~2min

## Overall Verdict
BLOCKED

## Blocking Findings

BLOCK-1: Commit content does not match milestone scope
- Pack title/summary claim: "Add tmux transport to bridge, enabling phone to view/control all Mac terminal windows bidirectionally. Relay multi-client support. iOS terminal renderer. Preserve existing Codex mode."
- Commit `6e1f7a0` (initial commit) tree contains only `LICENSE`.
- No bridge, tmux, relay, iOS renderer, or Codex code in the commit.
- `AGENTS.md` (read_only_files) is untracked — not part of the commit tree.
- Pack `changed_files: ["LICENSE"]` is correct for the diff but contradicts the scope entirely.
- Pack status `ready_for_review` is premature. No implementation exists to review against the claimed milestone.

BLOCK-2: Metadata fragmentation
- Pack lists `changed_files: ["LICENSE"]` and `read_only_files: ["AGENTS.md"]`.
- `validation: []` and `non_goals: []` are empty/"not recorded" — pack is incomplete for a milestone claiming substantial new transport and renderer work.
- A meaningful review pack for this scope would reference bridge protocol files, tmux integration code, relay client/server changes, and iOS terminal view code. None exist.

## Non-Blocking Findings

- LICENSE is standard Apache-2.0 boilerplate. No issue.
- AGENTS.md (untracked) has reasonable local-first project conventions.
- The pack appears to have been written for a planned milestone that hasn't been implemented yet.

## Plan Architecture Review

Plan document: `PLAN.md`. 独立评估，不 gate 阻拦。

### 需求匹配度

| 需求 | PLAN 方案 | 可行？ |
|------|----------|--------|
| 手机看所有 Mac 终端窗口 | tmux list-sessions → relay → iOS 列表 | ✅ |
| 手机开新终端 | tmux new-session -d via relay | ✅ |
| 双向内容同步 | node-pty data event → encrypt → broadcast | ✅ |
| 手机输入命令 | sendKeys → relay → tmux send-keys | ✅ |
| Mac/手机不冲突 | tmux 原生多 client attach 同一 session | ✅ |
| 保留 Codex 模式 | bridge transport 选择器，两套并行 | ✅ |

### 架构评价

tmux 路线是对的。不是自己管 pty 池，借 tmux 已有的 session 管理 + 多 client 能力：
- Mac 本地 tmux + 手机同时看同一 pane → tmux 原生支持
- 未来 Mac 本地没开 tmux → bridge 可以 spawn 新 session
- 现有 codex-transport、secure-transport、E2EE、QR → 全不动，只加平行 transport

Relay 多 client 改造约 10 行，侵入最小。

### 风险与壁垒

1. **node-pty 原生编译**（中）。依赖 Xcode CLT + node-gyp + arm64 native。PLAN 写了 fallback（child_process polling），但 polling 延迟高。建议 v1 先用 polling 出原型，node-pty 加速放后面。

2. **ANSI 渲染**（中）。v1 strip-all，iOS 纯文本+关键词着色。终端输出大量颜色/git diff/ls 着色/tmux status bar，纯文本可读性差。PLAN 分 v1/v2 合理，但用户预期需要管理。

3. **非 plan 问题**：PLAN 本身质量好，简洁无过度设计。问题是没有代码实现。

### 可信度结论

**PLAN 可信。能实现"手机看所有 Mac 终端+双向同步"。**

具体判断：
- tmux + transport 抽象复用 → 干净可维护
- relay 改 ~10 行 → 侵入极小
- E2EE/QR/Codex 不动 → 零回归风险
- 估算 ~960 行改动 → 对这类功能算精准
- Risk table 诚实

卡在没人动手，不是 plan 有问题。

## Boundary Check

- No out-of-scope files changed: yes (only LICENSE in commit)
- No forbidden external actions: N/A — no executable code to evaluate
- Validation evidence reviewed: no — pack says "not recorded"
