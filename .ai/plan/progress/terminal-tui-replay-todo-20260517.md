# Terminal TUI replay/resize 乱码专项 TODO

## 结论

当前先保留 `9251cc2` 之后的基线，不继续用小 patch 试探。这个问题不是快捷栏按钮问题，而是 Terminal live stream、tmux replay、SwiftTerm redraw、键盘 resize 之间的时序问题，需要单开专项处理。

## 问题现象

- 打开或创建 Claude/Kimi/mmd 这类 TUI 后，屏幕会出现旧内容和当前 TUI 混在一起的乱码/错位。
- 输入文字、切换、收起键盘、或触发 resize 后，画面通常会恢复正常。
- 后续一次尝试中出现过 `terminal/stream/replay` 循环刷屏，Bridge 日志不断出现 `terminal/stream/replay request target=(empty)` 和 `terminal/stream/replay ok`，同时手机端屏幕闪烁。

## 背景

- 当前 Terminal 使用 SwiftTerm 渲染 tmux control-mode 输出。
- Bridge 同时提供：
  - live output：tmux control-mode `%output` / `%extended-output`
  - replay：`capture-pane` 捕获当前 pane 内容后再喂给 SwiftTerm
  - resize：iOS 根据 SwiftTerm view 尺寸上报 cols/rows 给 Bridge，再 resize tmux pane/window
- TUI 程序依赖 ANSI control sequences 和准确终端尺寸；如果 replay/resize/live output 时序不稳定，SwiftTerm 很容易把旧 scrollback 当成新输出渲染，或者把旧尺寸下的 TUI 布局留在画面里。

## 已尝试

### 已保留

- `75dd9bd fix(ios): steady terminal fixed key controls`
  - 修复输入/收键盘固定按钮的 SwiftUI 幻影动画。
  - 固定 keybar 宽度、separator、stroke。
  - review 结论：无 blocking finding；后续只需清 unused helper。

- `178262b fix(ios): replay terminal agents by viewport`
  - 将 Claude/Codex/Kimi/mmd 这类 agent/TUI pane 从 full-history replay 改为 viewport replay。
  - 目标是避免 full-history tmux capture 把旧 scrollback 当 ANSI stream 重放。
  - 同时在 keyboard show/hide、resize 后做 debounce viewport replay。
  - 风险：这层可能仍会导致 replay 请求过多，后续如继续刷屏，需要重新评估。

- `9251cc2 revert(ios): restore previous terminal stream start`
  - 回退 `770cb29`，恢复上一版 stream start 行为。
  - 当前应以它为可用基线。

### 已确认有问题，不要恢复

- `770cb29 fix(ios): size terminal before streaming`
  - 尝试在 stream start 前先 `resizeTerminalPane`，并调整初始 resize/start 顺序。
  - 结果触发 `terminal/stream/replay` 循环刷屏、Bridge 日志刷 `target=(empty)`，手机屏幕闪烁。
  - 已由 `9251cc2` 回退。

## 后续 TODO

1. 建立复现矩阵：分别测 Claude/Kimi、mmd、普通 shell；场景包括创建时、执行 TUI 时、键盘弹出、收键盘/resize、切 pane。
2. 加 Debug tracing：只在 debug flag 下记录 redacted `paneId`、redacted `streamId`、`seq`、`phase`、`cols/rows`、SwiftTerm `bounds/dims`、keyboard frame。
3. 给 replay 加硬性幂等保护：同一 `streamId + paneId + cols/rows + keyboard state` 在 cooldown 内只能触发一次 replay。
4. 修正 `terminal/stream/replay request target=(empty)`：确认 iOS replay 请求是否缺少 `streamId`，Bridge 是否在日志里误把 stream replay 打成 empty target。
5. 拆分“刷新画面”和“replay 内容”：不要再把 `terminal/stream/replay` 当通用 redraw；优先研究 SwiftTerm 本地 `setNeedsDisplay` / cursor refresh / layout refresh。
6. 检查 tmux 时序：确认 `resize-window`、`refresh-client -C`、`capture-pane -e`、control-mode `%output` 谁先谁后。
7. 评估 agent/TUI 专用模式：必要时对 TUI 使用 viewport snapshot + live output 混合策略，而不是 full replay 或频繁 replay。
8. 最终验收标准：创建/执行 TUI 不出现旧内容叠加；键盘 show/hide 不刷屏；Bridge 日志不会连续重复 replay；普通 shell 不回退。

## 当前建议

短期不要继续在这条线上叠加 replay patch。下次专项从 tracing 和幂等保护开始，而不是直接改 stream/replay 时序。

## 2026-05-18 更新

- 最终 `main` 已到 `39d623d`，iOS 版本 `1.7.111 (149)`。
- `9d7bc77 fix(ios): avoid resizing shared tmux windows` 已解决手机 SwiftTerm stream 期间仍调用全局 `terminal/resize` 的问题。
- 关键结论：iPhone 不应再通过 `terminal/resize` 改共享 tmux window；SwiftTerm active stream 只更新本地 size / control client size，避免把 Mac 端压成手机宽度。
- Mac 上已经被 55 列尺寸写入的旧 scrollback 不会自动重排；这属于历史内容，不要把它当成新的 iOS renderer 回归。
- TUI 创建时乱码/旧内容叠加仍按本 TODO 单开专项；不要在稳定主线继续试探 replay/resize 时序。
