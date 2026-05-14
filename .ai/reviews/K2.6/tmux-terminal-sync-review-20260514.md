# tmux-terminal-sync Review - Tmux Terminal Sync & Multi-Backend

- Date: 2026-05-14
- Reviewer: K2.6
- CLI: claude-code
- Started: 2026-05-14T15:10:00+00:00
- Completed: 2026-05-14T15:10:30+00:00
- Duration: ~30s

## Overall Verdict
BLOCKED

## Blocking Findings

BLOCK-1: Declared scope not present in commit
- Pack summary claims: "Add tmux transport to bridge, enabling phone to view/control all Mac terminal windows bidirectionally. Relay multi-client support. iOS terminal renderer. Preserve existing Codex mode."
- Commit `6e1f7a0` is the Initial commit. Tree contains exactly one file: `LICENSE`.
- No bridge code, no tmux transport, no iOS renderer, no relay code, no Codex mode logic exists.
- `AGENTS.md` exists in working tree but is untracked — not part of the commit.
- Pack `changed_files: ["LICENSE"]` is accurate for the commit, but contradicts the summary/scope.
- Pack status: `ready_for_review` is incorrect — there is no implementation to review.

## Non-Blocking Findings

- LICENSE is standard Apache-2.0, unmodified.
- `AGENTS.md` contains reasonable local-first guardrails; suggest ensuring it is committed if intended as project policy.

## Plan Review (PLAN.md)

Reviewed `PLAN.md` at repo root. Verdict: **架构方向对，Phase 3 iOS 终端渲染路径错误，3 个硬壁垒必须解决。**

### BLOCK-P1: 终端渲染器缺失（最大壁垒）

Plan 明确排斥 xterm.js/WebKit，主张"纯 SwiftUI Text + strip ANSI"。终端不是纯文本流。
- `vim`/`htop`/`lazygit` 依赖光标控制 + 屏幕 buffer，纯 Text 无法渲染
- `\r` 回车进度条、清屏、行编辑会显示错乱
- 无 rows/cols 同步 — tmux 按 Mac 端尺寸渲染，手机端显示断裂
- Plan 漏了虚拟屏幕 buffer、光标跟踪、终端尺寸协商

**修复方向**: WKWebView + xterm.js（最成熟）；或 TextKit + 自建 ANSI parser + 虚拟屏幕 buffer（工作量大）。纯 Text 不可行。

### BLOCK-P2: 手机输入方案空白

Plan 完全没有设计 iOS 软键盘的终端输入方案。终端核心操作依赖物理键位：
- `Ctrl+C` 中断、`Ctrl+D` EOF、`Tab` 补全、`↑↓` 历史、`Ctrl+A/E` 行首尾

没有自定义 input accessory view 提供这些键位，方案无法实用。

### BLOCK-P3: "所有终端窗口"有盲区

用户核心需求是"电脑上所有终端窗口"。Plan 只覆盖 tmux session。
- iTerm / Terminal.app 里直接跑的 shell（没用 tmux）**完全看不到**
- 要么接受"仅限 tmux"的边界（需明确告知用户），要么改架构让 bridge 直接 spawn pty 管理所有终端

### 非阻塞意见

| Phase | 可信度 | 备注 |
|-------|--------|------|
| Relay 多 client | 低 | "~10 行"太乐观。广播 + backpressure + 断连清理，实际 30-50 行 |
| tmux-transport.js | 可信 | node-pty + tmux 命令，straightforward |
| iOS 终端渲染 | **不可信** | 必须推倒重来 |
| 模式切换 | 可信 | transport selector 简单 |
| 自动发现 | 可信 | tmux list-sessions straightforward |

- ANSI 处理 v1 至少保留基本颜色，不能全 strip。全 strip 体验太差。
- 并发输入竞争：tmux 多 client attach 同一 session 时，两个端同时 send-keys 会 interleave，不是"互不影响"
- 工作量估算对纯文本流场景大致合理，但终端渲染器重做会大幅超估

## Boundary Check

- No out-of-scope files changed: yes (only LICENSE in commit)
- No forbidden external actions: N/A — no code to evaluate
- Validation evidence reviewed: no — pack says "not recorded"
