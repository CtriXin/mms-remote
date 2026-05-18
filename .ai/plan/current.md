# Current Handoff — MMS Remote Active Iteration

Timestamp: 2026-05-18T06:58:28-04:00
Owner: codex
CLI: codex
Model: gpt-5
Task ID: main-final-docs-cleanup-20260518
Status: `main` 已完成 Terminal pane / SwiftTerm ghost / localization 最终合并；handoff 文档已刷新。App 代码稳定点是 `39d623d`，当前文档基线是 `2874a88`。
Next Action: 继续从 `main` 开发；不要把本地工具缓存提交。Terminal TUI replay/resize 乱码后续单开专项，不在当前稳定主线继续试探。
Current Commit Before This Docs Commit: `2874a881901d2727d05b4ba46b2a00ac61c635bc`
App Code Baseline: `39d623db9c2e6854a15d40666b9dce8d3f42d077`

## Key Truth

- 当前分支：`main`；本次文档整理前 HEAD 是 `2874a88 docs: record terminal final handoff`。
- App 代码最终合并点：`39d623d merge: adopt localization polish`；iOS 版本是 `1.7.111 (149)`。
- 已安装设备：`song的iPhone`；`iPhone 15 ProX雨` 当时为 `unavailable`，未安装。
- 关键修复：`9d7bc77 fix(ios): avoid resizing shared tmux windows`，避免手机 SwiftTerm stream 把 Mac tmux window 压成手机尺寸。
- 保留稳定线：`144fc1b` 之后的 Terminal 稳定回滚 + 后续小修；不要恢复 reconnect/glass 大改中导致 flicker/resize/scroll 的实现。
- 保留 bottom `Sessions` drawer；不要恢复旧 left sidebar Terminal 实验。
- Terminal TUI 创建时乱码/旧内容叠加仍是专项 TODO；先从 tracing 和 replay 幂等保护做，不要继续 trial-and-error。
- `mms-remote-bridge/package.json` 仍是 `1.7.64`；下一次涉及 Bridge release/version 时显式同步，不要顺手乱改。
- Upstream Remodex 只作为参考：Apache-2.0 attribution 保留；不整合 upstream direct SSH/GhosttyKit/Citadel；大 PR 暂不投入。
- 本地生成目录 `.codegraph/`、`.omc/`、`mms-remote-bridge/.omc/`、`tmp/` 不应提交；只记录/忽略。

## Read Next

- `.ai/plan/progress/terminal-pane-session-handoff-20260517.md`
- `.ai/plan/progress/terminal-tui-replay-todo-20260517.md`
- `.ai/plan/progress/upstream-remodex-watchlist-20260518.md`
- `.ai/plan/v2-roadmap.md`
- `.ai/plan/packet.json`
- `AGENTS.md`
