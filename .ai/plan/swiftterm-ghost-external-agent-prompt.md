# SwiftTerm Ghost 外部 Agent 调研 Prompt

请继续项目：`/Users/xin/auto-skills/CtriXin-repo/mms-remote`

你的任务不是直接写修复代码。你的任务是：独立调研 iOS SwiftTerm ghost/影子问题，给出可落地根因判断，并把结论写回项目文档。

## 必读文件

按顺序读：

1. `AGENTS.md`
2. `.ai/plan/current.md`
3. `.ai/plan/progress/swiftterm-ghost-multiagent.md`
4. `.ai/plan/swiftterm-ghost-multiagent-prompt.md`
5. `Docs/swiftterm_ghost_analysis.md`
6. `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`
7. `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`
8. `mms-remote-bridge/src/terminal-stream-hub.js`
9. `mms-remote-bridge/src/tmux-control-adapter.js`
10. `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift`
11. `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/iOS/iOSCaretView.swift`
12. `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/CaretView.swift`

## 背景

这是一个 local-first iOS + Mac Bridge 项目。iOS 端有 Terminal UI，使用 SwiftTerm renderer 展示 tmux/terminal stream。Bridge 侧从 tmux 取 replay/live output，通过 secure/local transport 推给 iOS。

当前最新可用安装点：

- iOS version/build: `1.7.53 build 91`
- device: `song的iPhone`
- SwiftTerm revision: `9ad1b190b7b6f3dd072063c7d86535e2298f0aad`
- latest SwiftTerm `602be53` 试过 generic build，失败原因：缺 Metal Toolchain；不要直接建议无条件升级 latest。

项目规则：

- 中文简体回复，technical terms 保持 English。
- 不要跑 Xcode tests，除非用户明确要求。
- iOS code change 必须 bump version/build。
- 安装只到 `song的iPhone`。
- 不要泄露用户 private relay endpoints。
- 不要 revert unrelated dirty files。
- 本任务默认 research/docs-only；不要直接改 iOS code。

## 重点问题

iOS SwiftTerm 输入后出现视觉 ghost/影子/双字符残留。

关键性质：

- 用户看到像字符重复/影子。
- 切换出去再回来，或刷新/replay/full redraw 后，影子消失。
- 所以高度怀疑是 visual/compositor/rendering stale artifact，不是 terminal buffer 真实重复。
- 不能用闪屏式 full replay/full refresh 当最终方案，因为用户明确觉得体验差。
- SwiftTerm 不能禁用；用户明确反对禁用 SwiftTerm。

## 之前现象 / 已经踩过的坑

历史中出现过多个相关但不同症状：

1. 双字符/影子：输入后出现，切换/刷新后消失。
2. 闪一下：用 replay/full redraw 清 ghost 时能清掉，但 UI 每次闪，用户不接受。
3. 空白启动：把 SwiftTerm stream 改成 `replay: false` live-only 后，启动进入 Terminal 可能空白；已恢复为 startup viewport replay。
4. `cd`/`pwd` 显示异常：`1.7.49/87` 的 RunLoop/default-mode stream drain 方案破坏 echo/order，用户反馈更差；不要重试。
5. 乱码/换行错：Bridge CR/LF normalization 后已改善。

已失败或不要重复的方向：

- 不要禁用 SwiftTerm。
- 不要把 replay/full-screen refresh 当最终修复。
- 不要重试 `1.7.49/87` RunLoop/default-mode stream drain。
- 不要把 hidden input proxy + mobile cursor overlay + CaretView quarantine/addSubview block 当主修复；这条已经试过，ghost 仍在，复杂度高。
- 不要把 startup stream 改成纯 `replay: false`；之前导致空白启动。
- 不要直接升级 SwiftTerm latest，除非先解决 Metal Toolchain/build 问题。

## 现在现象

当前 `1.7.53 build 91` 用户反馈：

- 空白启动：已解决。
- `cd` 显示异常：已解决。
- 乱码：已解决。
- SwiftTerm visual ghost/影子：仍存在。
- 切换/刷新后 ghost 消失。
- 现在问题范围收敛为：SwiftTerm renderer/live input 后视觉残留。

## 当前实现要点

iOS：

- `SwiftTerminalHubView.swift` 中 SwiftTerm stream start 当前使用 startup viewport replay：`replay: true, replayViewportOnly: true`。
- `replaysSwiftTermAfterInput = false`，输入后不再 replay，避免闪屏。
- `SwiftTerminalCanvasView.swift` 已恢复 native SwiftTerm input/caret path。
- `applyTerminalFontIfNeeded` 避免每次 SwiftUI update 都重设 font。

Bridge：

- `terminal-stream-hub.js` 管 replay/live stream。
- `tmux-control-adapter.js` 已做 output normalization：bare LF -> CRLF，duplicate adjacent CR collapse，private glyph fallback。
- Node tests 当前曾通过 `329/329`。

## 已有 multiagent 结论

已有两个 agent 给过方向，但还需要你独立验证，不要盲信。

### Peirce 结论

主嫌：SwiftTerm iOS renderer dirty-rect/background clear 与 `UIScrollView.contentOffset` 坐标不一致。

理由：

- `AppleTerminalView.draw` 用 `dirtyRect` 清背景，但绘制 visible rows 又用 `contentOffset` 推导。
- SwiftTerm 源码自己有 iOS dirtyRect/scroll TODO。
- `updateDisplay()` cursor/redraw transaction 可能交错。
- `CaretView` 会放大影子感，但 wrapper 层 quarantine 已失败，不是完整根治。

建议 patch：

- SwiftTerm source-level：iOS draw 时清 `visibleRect = CGRect(x:0, y:contentOffset.y, width:bounds.width, height:bounds.height)`，或逐行 clear 即将绘制的 visible rows。
- cursor：invalidate old/new caret frame union；必要时 cursor 不画 glyph，只画 bar/underline。
- app wrapper：`feedPreservingScroll` 只在用户手动滚动时启用；恢复 offset 后显式 invalidate visible rect。

### Kierkegaard 结论

辅助风险：Bridge replay/live/input order 仍需 trace。

理由：

- viewport replay 是 `tmux capture-pane` 文本重建，不是 raw terminal state；末尾强行 CRLF 可能推错 cursor。
- live during replay buffering 用文本 heuristic，ANSI/partial chunk 可能漏重复 tail。
- iOS input 每次 send 独立 async Task，没有 per-pane input queue；Bracketed paste start/body/end 可能乱序。

建议 diagnostic：

- Bridge 记录 streamId suffix、paneId、seq、type、phase/replay flag、byteLength、sha256、first/last hex、buffer/drop count。
- iOS 记录 seq gap、feed order、reset、decoded byte hash、first/last hex、dims。
- 用 `printf 'LONG-LINE-1234567890\r\033[Kshort\n'` vs 不带 `ESC[K` 对照，区分 terminal clear 语义和 app ghost。

## 你要回答的问题

请明确回答：

1. 你认为当前 ghost 的最高概率根因是什么？给概率和证据。
2. 这是 SwiftTerm renderer/compositor 问题、CaretView 问题、Bridge bytes/order 问题，还是 iOS host integration 问题？
3. 哪些旧方案必须禁止继续尝试？为什么？
4. 最小 diagnostic patch 是什么？具体到文件、函数、记录字段。
5. 最小 real patch 是什么？具体到文件、函数、核心代码思路。
6. 如何验证？不能跑 Xcode tests。请给手动 smoke + build/test 命令。
7. 如果你认为无解或成本过高，给出可接受降级方案，但不能禁用 SwiftTerm。

## 必须落地的文档

请不要只在聊天里回答。请把结果写入项目文件：

1. 新建或更新：`.ai/plan/progress/swiftterm-ghost-external-review.md`
2. 追加更新：`Docs/swiftterm_ghost_analysis.md`

文档要求：

- 标明 timestamp、agent/model、scope、status。
- 写清：背景、之前现象、现在现象、复现路径、已失败方案、根因排序、推荐 diagnostic、推荐 patch、验证计划、风险。
- 不要写 private relay endpoint。
- 不要创建 repo root 临时报表。
- 如果只做 research/docs，不要 bump version/build。

## 可用验证命令

Research/docs-only 时只需：

```bash
git diff --check
python3 - <<'PY'
import pathlib
for p in ['.ai/plan/progress/swiftterm-ghost-external-review.md', 'Docs/swiftterm_ghost_analysis.md']:
    print(p, pathlib.Path(p).exists())
PY
```

如果后续明确允许做代码修复，再用：

```bash
HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test --prefix mms-remote-bridge
xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData-ghost-next CODE_SIGNING_ALLOWED=NO build
HOME=/Users/xin xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'id=00008150-0008781C36D9401C' -derivedDataPath .build/DerivedData-device build
xcrun devicectl device install app --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 .build/DerivedData-device/Build/Products/Debug-iphoneos/CodexMobile.app
```

## 输出格式

最后回复请短：

- 结论一句话
- 已写文件路径
- 最关键 root cause
- 下一步 patch 建议
- 验证结果
