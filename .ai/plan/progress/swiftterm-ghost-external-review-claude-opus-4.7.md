# SwiftTerm Ghost External Review — claude-opus-4.7

- Timestamp: 2026-05-16T (UTC-4) external review
- Agent / Model: `claude-opus-4.7` (Opus planner via local plan-gate)
- Scope: research/docs-only, no iOS code edits, no version bump
- Status: independent conclusion recorded
- Isolation note: separate file per agent. Parallel agents must NOT merge with `swiftterm-ghost-external-review.md` or this file without conflict review.

---

## 0. Reproducibility 摘要

- Device anchor: iOS `1.7.53 build 91` on `song的iPhone`.
- Symptom space (current, post-1.7.53/91):
  - blank startup / `cd` 显示 / 乱码 — fixed.
  - 输入后 SwiftTerm visual ghost/影子 — 仍存在。
  - 切换 tab/scene 回来 或 full replay — ghost 消失（但 replay 会闪屏）。
  - tmux buffer 真值正确，ghost 仅是 GPU layer 视觉残留。
- Reproducer 建议（验证步骤里展开）: 在底部连续 `printf` 或重复 `ls`/`echo` 多次，watch cursor 周围 cell glyph 重影；用 `printf 'LONG-LINE-ABCDEFG\r\033[Kshort\n'` 对比 with/without `ESC[K`。

---

## 1. 当前代码状态 (与历史 Docs 不同)

历史 `Docs/swiftterm_ghost_analysis.md` 里 70% 概率的 "addSubview 拦截 CaretView quarantine" 路径，**在当前 `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift` 中已不存在**：

- `SwiftTerminalCanvasView.swift` 现在只有 623 行（曾经 ~1700）。
- 没有 `quarantineSwiftTermCaretViews`、`mobileCursorView`、`flushDisplayAfterOutboundInput`、`addSubview` override、hidden input proxy、`MMSStreamInputProxyTextView` 类。
- `MMSStreamTerminalView` 现在的全部 wrapper hook 只有：
  - `feedPreservingScroll`：只在用户**不在底部**时保留 `contentOffset.y` 1.5–2.0s。
  - `setContentOffset` override：仅在用户手势期间或保留窗口内 clamp Y。
  - `layoutSubviews`：clamp `contentOffset.x == 0`。
  - `applyTerminalFontIfNeeded`：避免重复 reset font。
  - `paste` / `keyCommands`：键盘快捷键。
- 输入/caret 走 **SwiftTerm 原生路径**：CaretView 由 `AppleTerminalView.updateCursorPosition()` 添加/移除/move/setText，app 完全不再拦截。

含义：
- Peirce 原假设中"CaretView quarantine race"已经**不适用**（quarantine 代码已被移除）。Bug 仍在，说明 app-wrapper quarantine **不是**也不曾是根因。
- 当前所有可能解释必须落在三层之一：
  (a) **SwiftTerm 原生 iOS renderer / compositor 行为**（最可能）。
  (b) Bridge bytes/order（可能性低，buffer 已正确）。
  (c) iOS host integration：`feedPreservingScroll` + `setContentOffset` override 与 SwiftTerm 自身 contentOffset 行为交互。

---

## 2. SwiftTerm 源码关键证据

文件：`.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift`

### 2.1 iOS draw path (`drawTerminalContents`, line ~1037-1046)

```swift
#if os(iOS) || os(visionOS)
let cellHeight = cellDimension.height
let firstRow = Int(contentOffset.y / cellHeight)
let lastRow = firstRow + Int(ceil(bounds.height / cellHeight))
```

行首/行尾用 **`contentOffset.y`** 推导，不用 `dirtyRect.minY`。注释承认 UIKit coalesces dirty rects across scroll updates。

### 2.2 iOS update path (`updateDisplay`, line ~1488-1491)

```swift
#else
// TODO iOS: need to update the code above, but will do that when I get some real
// life data being fed into it.
setNeedsDisplay(bounds)
#endif
```

iOS 永远 invalidate **整个 visible bounds**，无 row-level dirty rect。macOS 有 row 区间的 region 精确化。**作者自承 iOS 路径 TODO 未完成。**

### 2.3 cursor 移动 (`updateCursorPosition`, line ~1505-1531)

```swift
} else if terminal.cursorHidden == false && caretView.superview != self {
    addSubview(caretView)
}
...
caretView.frame.origin = CGPoint(x: lineOrigin.x + ..., y: lineOrigin.y)
caretView.setText (ch: buffer.lines [vy][buffer.x])
```

关键点：
- `caretView.frame.origin` 直接赋值，没有 `CATransaction.setDisableActions(true)` 包裹。`UIView.frame` 在普通模式下是 implicit animatable（虽然非 animation block 内多数 implicit anim 被 UIKit 默认 disable，但在某些 transaction context 下仍会生效）。
- `caretView.setText(ch:)` ([iOSCaretView.swift:80-87]) 重建 CTLine 并 `setNeedsDisplay(bounds)` of the CaretView，CaretView 在 block-cursor style 下会把 cell 字符 fill 进 cursor 区。

### 2.4 linefeed contentOffset 强制 (`linefeed`, line ~1253-1267)

```swift
open func linefeed(source: Terminal) {
    ...
    contentOffset = CGPoint (x: 0, y: CGFloat (displayBuffer.lines.count-displayBuffer.rows)*cellDimension.height)
```

SwiftTerm 每次 linefeed 强制 `contentOffset` 到底部 — 与 app 的 `feedPreservingScroll` 在 user-not-at-bottom 情形发生 ping-pong：
1. SwiftTerm 内部把 `contentOffset.y` 推到底部。
2. `feedPreservingScroll` 之后用 `super.setContentOffset(restoredY)` 推回去。
3. SwiftTerm 16ms 后 `updateDisplay() → setNeedsDisplay(bounds)`，此刻 `bounds.origin == restoredY`（已恢复）。
4. 但 `drawTerminalContents` 用 `contentOffset.y` 推 firstRow，此刻也是 restoredY → 与 invalidation rect 一致。
5. **底部场景下 `feedPreservingScroll` 不参与（`shouldRestore == false`）**：所以 ghost 在底部仍出现意味着 root 与 contentOffset ping-pong 关系不大。

### 2.5 `drawTerminalContents` 不显式 clear row 背景

iOS 分支无 row-level background fill before glyph draw。背景靠 per-segment background fill（仅覆盖该 segment 的字符宽度）。若 cell 内容从 `'X'` 改成 ` `（空格），terminal 内部 `setNeedsDisplay(bounds)` 触发整 layer 重绘，**但** UIView 默认 `clearsContextBeforeDrawing == true` 会清 dirtyRect，所以理论上不应有 stale 文本。除非：
- CaretView 的 layer 独立绘制并 commit 到 GPU，CaretView 的 dirtyRect 仅 = 自身 bounds（一个 cell 大小），更新与 TerminalView 重绘的 transaction 顺序不一致。

---

## 3. 根因排序（我的独立判定）

把概率给到三个层级，不盲从前两个 agent。

### 3.1 主嫌 (概率 ~55%): **CaretView 独立 layer 与 TerminalView layer 的 commit 顺序竞争 + iOS-only 缺 row-level dirty rect**

机制：
- 用户按键 → echo bytes → `feed(byteArray:)` → terminal buffer 写入新字符 → `terminal.refresh(...)` 把 dirty range 标记 → `queuePendingDisplay()` 16ms 后 `updateDisplay()`。
- `updateDisplay()` 先 `updateCursorPosition()`，**修改 CaretView.frame.origin 并 setText 新字符**。CaretView 自己 `setNeedsDisplay(bounds)`。
- `updateDisplay()` 然后 `setNeedsDisplay(bounds)`（TerminalView 全 viewport）。
- Core Animation commit phase：两个独立 layer 各自重画。**TerminalView layer 重绘 viewport，新 cell 内容会出现**；CaretView layer 也重绘自己。**但 CaretView 的 frame 移动到了新 origin，旧 origin 处的 GPU 残像** = 旧 cursor 位置的 block-fill + 字形（来自上一帧 `setText`）。
- 旧 origin 处底下的 TerminalView 已经被 invalidate 并重画（含 buffer 真值）→ 这一帧理论上覆盖；但 `setNeedsDisplay(bounds)` 在 iOS UIScrollView 实现里**经过 tile-based caching**，UIKit 可能不把 tile 整块刷新（CALayer `drawsAsynchronously` / minification 行为）。最常见结果：旧 CaretView 区域**残留上一帧 block-cursor 的 colored fill 像素**。
- "切换出 view 再回来" → 整个 layer hierarchy 重新 attach → tile cache 被 invalidate → ghost 消失。
- "replay/full redraw" → buffer reset → 强制重画整层 → 闪屏。

证据匹配：
- ✅ buffer 是对的（CaretView 不影响 buffer，只影响 cursor 视觉层）。
- ✅ 输入触发（每次 `updateCursorPosition` 才 setText）。
- ✅ 切换消失（layer reattach 刷掉 tile cache）。
- ✅ replay 清掉（强制 reset + 全画）。
- ✅ ghost 形状是字符（CaretView block style + glyph fill）。
- ✅ ghost 位于 cursor 之前的位置（旧 frame.origin）。
- ✅ 不在 macOS 表现（macOS 路径用 row-region setNeedsDisplay；iOS path 是作者 TODO）。

反证 / 风险：
- ⚠ 如果是 implicit animation，cursor 移动也应慢动画化，但用户没报告"cursor 滑动"。但 UIKit 在非 animation block 中 frame 赋值通常**不**走 animation；这点弱化 implicit anim 假设，强化 tile-cache stale 假设。
- ⚠ 如果是 tile cache，理论上轻量 `layer.setNeedsDisplay()` on TerminalView 即可清；但 SwiftTerm 已经 `setNeedsDisplay(bounds)` 而 ghost 仍在，说明 iOS UIScrollView 对 view-level invalidate 的实际刷新粒度 < bounds（典型 UIScrollView `tile = 256pt` 行为）。

### 3.2 次嫌 (概率 ~25%): **`drawTerminalContents` iOS 分支 firstRow/lastRow 与 buffer.yDisp 偏移漂移**

`firstRow = Int(contentOffset.y / cellHeight)` 假设 `contentOffset.y` 永远 == `displayBuffer.yDisp * cellHeight`。但：
- `feedPreservingScroll` 主动 super.setContentOffset(restoredY)；
- SwiftTerm `linefeed` 主动 `contentOffset = ...` 设到底部；
- `layoutSubviews` clamp x；
- 用户手势 dragging。

任一时刻可能短暂打破 `yDisp == contentOffset.y / cellHeight`。`drawTerminalContents` 在此时画的 row index 与 setNeedsDisplay invalidate 的 rect 错位，**导致某 row 旧像素未被 invalidate 但 firstRow 推进了 → 留下旧 cell glyph**。

证据匹配：
- ✅ 仅 iOS 出现（iOS 分支才用 contentOffset.y 推 firstRow）。
- ✅ 输入触发（linefeed/scroll snap 引发 contentOffset 写）。
- ⚠ 不完全解释"切换消失"，除非切换触发 yDisp/contentOffset 重新同步。

### 3.3 辅嫌 (概率 ~15%): **`setNeedsDisplay(bounds)` 在 UIScrollView 上对子 layer tile 的非完整 invalidation**

iOS `TerminalView : UIScrollView`，UIScrollView 内部有 tile system。`setNeedsDisplay(bounds)` 对 `self`（scrollview 本体）的 `layer` 触发重绘。但 `UIScrollView` 在 contentSize > bounds 时往往使用 `tiledLayer`。SwiftTerm 当前 iOS path 把 setNeedsDisplay 的 region 直接传 `bounds`（不是 content-space full size）。Tile 系统可能用更细粒度做 culling 而漏刷某些 cell 区域。

证据匹配：
- ✅ 与 Top-3 共因；不是独立根因。
- ⚠ 难以 isolate，只能用 diagnostic 验证。

### 3.4 极低 (概率 ~5%): Bridge stream race

`feedPreservingScroll` 块内 `terminalView.feed(byteArray: bytes[...])` 是同步 push，buffer 已经 `tmux-control-adapter.js` 做 CR/LF normalization；`terminal-stream-hub.js` 控制 replay/live 顺序。用户已经确认 `cd`/`pwd` 显示正常，乱码消失，**buffer 真值正确** ⇒ Bridge 几乎不会是视觉 ghost 的根因；最多是 Kierkegaard 担忧的次级风险。

---

## 4. 必须禁止的旧方案 (一致)

不要再试：
1. **禁用 SwiftTerm** — 用户明确拒绝。
2. **闪屏式 replay/full redraw 作为最终修复** — 用户体验差。
3. **`1.7.49/87` RunLoop/default-mode stream drain** — 已经破坏 echo/order。
4. **hidden input proxy + mobile cursor overlay + CaretView quarantine/addSubview block** — 已被移除且没消除 ghost；复杂度高、收益负。
5. **startup `replay: false`** — 空白启动 regression。
6. **升级 SwiftTerm latest `602be53`** — 当前 Xcode 缺 Metal Toolchain，build 失败。
7. **在 `feedPreservingScroll` 块外加 hack 调用 `contentOffset` reset** — 与 SwiftTerm `linefeed` 强制 contentOffset 形成新 ping-pong。
8. **改 Bridge dedupe/normalization 解 ghost** — 与 buffer 真值无关。

---

## 5. 最小 Diagnostic Patch（先验证根因，再决定修）

**目标：用一次部署验证 §3.1 vs §3.2 vs §3.3。不改业务行为，仅打 telemetry。**

### Patch D1：iOS 端 instrument TerminalView 重绘和 CaretView 位置（research-only）

文件：`CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`

在 `MMSStreamTerminalView` 类中临时加（仅 debug build，用 `#if DEBUG` 隔离）：

```swift
#if DEBUG
private var ghostDebugFrameCounter: Int = 0

override func setNeedsDisplay() {
    ghostDebugFrameCounter &+= 1
    if ghostDebugFrameCounter % 30 == 0 {
        NSLog("👻 setNeedsDisplay() bounds=\(bounds) contentOffset=\(contentOffset) contentSize=\(contentSize)")
    }
    super.setNeedsDisplay()
}

override func setNeedsDisplay(_ rect: CGRect) {
    NSLog("👻 setNeedsDisplay(rect=\(rect)) bounds=\(bounds) contentOffset=\(contentOffset)")
    super.setNeedsDisplay(rect)
}

override public func draw(_ rect: CGRect) {
    NSLog("👻 draw(rect=\(rect)) bounds=\(bounds) contentOffset=\(contentOffset)")
    super.draw(rect)
}

override func addSubview(_ view: UIView) {
    let className = String(describing: type(of: view))
    if className.contains("CaretView") {
        NSLog("👻 addSubview(CaretView) frame=\(view.frame)")
    }
    super.addSubview(view)
}
#endif
```

记录字段：`bounds`、`contentOffset`、`contentSize`、`rect`，以及 CaretView 重 attach 时机。

预期判别：
- 如果 `setNeedsDisplay(rect)` 的 rect 与之后 `draw(rect)` 的 rect 大小一致且覆盖 viewport，但 ghost 仍发生 → 根因是 **CaretView layer 与 TerminalView layer 的 GPU commit race**（§3.1）。
- 如果 rect ≠ viewport 全部 → 根因是 **iOS path setNeedsDisplay 没覆盖到旧 cursor 行**（§3.3）。
- 如果 `contentOffset.y / cellHeight ≠ yDisp`（需要再 log `terminal.displayBuffer.yDisp`）→ §3.2。

### Patch D2：Bridge 端 stream telemetry（仅在 §3.1/3.2 都被验否时启用）

文件：`mms-remote-bridge/src/terminal-stream-hub.js`

emit/replay/flush 处加（隔 dev flag）：
- `streamId.slice(-6)`, `paneId`, `seq`, `type`, `phase`（replay/live）, `byteLength`, `sha256` 前 8 位, `firstHex8`, `lastHex8`, `bufferedDrops`。
不要 log full payload（隐私 + size）。**不要** log `sessionId` / pairing token。

文件：`mms-remote-bridge/src/tmux-control-adapter.js`

normalize 前后各打一次：`inSha`, `outSha`, `bareLfCount`, `crCollapsedCount`。

iOS 端 `feed` 入口 log `bytesSha8`, `seqGap`, `feedOrder`, `byteCount`。

判别：iOS 收到的 sha8 与 Bridge 发出的 sha8 一致 ⇒ Bridge 无关，根因在 renderer。

### Diagnostic 部署最小命令（research-only）

```bash
cd /Users/xin/auto-skills/CtriXin-repo/mms-remote
git diff --check
python3 - <<'PY'
import pathlib
for p in ['.ai/plan/progress/swiftterm-ghost-external-review-claude-opus-4.7.md']:
    print(p, pathlib.Path(p).exists())
PY
```

iOS instrument 部署（**仅当用户明确允许做 iOS 改动后**才执行）：
```bash
HOME=/Users/xin xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'id=00008150-0008781C36D9401C' -derivedDataPath .build/DerivedData-device build
xcrun devicectl device install app --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 .build/DerivedData-device/Build/Products/Debug-iphoneos/CodexMobile.app
```

---

## 6. 最小 Real Patch（确认 §3.1 后）

**前提：先用 §5 D1 验证 §3.1 是主嫌。**

### Patch R1（最小、无闪、不改 SwiftTerm 源码）

App 侧每次"输入回显完成后"，对 cursor 周围两个 cell 区做 **layer-level 精确 invalidation**，强制 tile cache 失效，而不是全屏 replay。

文件：`CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`

`MMSStreamTerminalView` 内加（注意 `caretView` 是 SwiftTerm internal 属性，需 KVC 访问 — 若 access 失败则改用第二备选）：

```swift
private func invalidateCursorNeighborhood() {
    let cellWidth = max(1, contentSize.width / max(1, CGFloat(getTerminal().cols)))
    let cellHeight: CGFloat = {
        let rows = max(1, getTerminal().rows)
        return contentSize.height / CGFloat(rows + getTerminal().getTopVisibleRow())
    }()
    // 取 SwiftTerm 当前 cursor 屏幕坐标。
    // 简化：用 contentOffset+bounds 估算可视 cursor 行；精确版需借助 caretView frame，但 caretView 是 internal。
    // 这里做一个稳健 fallback：invalidate 整个最后 viewport 行 + cursor 左右一格。
    let h = cellHeight * 2
    let y = max(0, contentOffset.y + bounds.height - h)
    let rect = CGRect(x: 0, y: y, width: bounds.width, height: h)
    super.setNeedsDisplay(rect)
}
```

注意：上面 cellHeight 估算非常粗糙；**真正可行的最小 real patch 是在 `feedPreservingScroll` 之后调用 `super.layer.setNeedsDisplay()`**：

```swift
func feedPreservingScroll(_ operation: () -> Void) {
    layoutIfNeeded()
    let previousY = clampedVerticalOffset(contentOffset.y)
    let shouldRestore = maxVerticalOffset > 0 && !isNearBottom()

    isApplyingStreamFeed = true
    operation()
    isApplyingStreamFeed = false

    // R1 fix: tile-cache invalidation hint, no flash
    self.layer.setNeedsDisplay()      // ← 新增
    // 注意：这是 layer-level 全 invalidate；与 setNeedsDisplay(bounds) 不同，
    // 它通知 CALayer 整 surface tile cache 失效，但 UIKit 重画仍以 draw(_:) 节流，
    // 不会产生 replay flash（因为不 reset buffer）。

    guard shouldRestore else { return }
    layoutIfNeeded()
    let restoredY = clampedVerticalOffset(previousY)
    preservedScrollY = restoredY
    preserveScrollUntil = ProcessInfo.processInfo.systemUptime + 2.0
    super.setContentOffset(CGPoint(x: 0, y: restoredY), animated: false)
}
```

并在 SwiftTerm `feed(byteArray:)` 完成后 throttle 调用一次（每 ~33ms 最多一次），避免重画风暴。

### Patch R2（如果 R1 不够）

需要改 SwiftTerm 源码（fork or local patch）。最小改动：

文件（fork 后）：`Sources/SwiftTerm/Apple/AppleTerminalView.swift` line ~1488-1491

```swift
#else
// iOS: invalidate visible viewport in **content coordinate space**, not the
// stale bounds rect captured at queue time.
let visibleRect = CGRect(x: 0, y: contentOffset.y,
                         width: bounds.width, height: bounds.height)
setNeedsDisplay(visibleRect)
// hint Core Animation that backing tile cache is dirty
layer.setNeedsDisplay()
#endif
```

并在 `updateCursorPosition()` 中包裹 frame 赋值：

```swift
CATransaction.begin()
CATransaction.setDisableActions(true)
caretView.frame.origin = CGPoint(x: ..., y: ...)
CATransaction.commit()
caretView.setText(ch: buffer.lines[vy][buffer.x])
```

避免 CaretView frame 走 implicit animation。

### Patch R3（极端备选，降级方案）

如果 R1/R2 均无效：在 input echo 路径上做 **per-row scope partial replay**（仅对 cursor 当前 row 调用 SwiftTerm 的 row-level invalidate API），不动其他 row，不闪整屏。需要 SwiftTerm 暴露 `setNeedsDisplay(rows: startY..endY)` API（当前是 internal）。

**不接受** Patch：禁用 SwiftTerm、全屏 replay 闪屏、`replay: false`-only。

---

## 7. 验证计划（不跑 Xcode tests）

1. **Diagnostic 阶段**：
   - 安装含 §5 D1 的 build 到 `song的iPhone`。
   - 触发：在底部连续 `echo a`/`echo b`/`ls` 多次，再用 `printf 'LONG-LINE-ABCDEFG\r\033[Kshort\n'` 对照。
   - 通过 `idevicesyslog` / Console.app 抓取 `👻` 前缀 log，对比 setNeedsDisplay rect、draw rect、bounds、contentOffset 时序。
   - 判定 §3.1 vs §3.2 vs §3.3。

2. **R1 验证阶段**：
   - 应用 R1，安装到 `song的iPhone`。
   - smoke：输入 5×ASCII、连发 ENTER、`ls -la`、scroll 上下、再输入。
   - 通过：ghost 不再出现，且无闪屏，且无 cursor 滑动 animation。
   - 失败回退：撤掉 R1，跳到 R2。

3. **R2 验证阶段**（fork SwiftTerm 后）：
   - 同 smoke。
   - 同时跑 Bridge 单测确认 stream 行为未受影响：
     ```bash
     HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test --prefix mms-remote-bridge
     ```
   - Xcode build verify:
     ```bash
     xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData-ghost-next CODE_SIGNING_ALLOWED=NO build
     ```

4. **版本号**：
   - 任何 iOS code change（含 D1 instrument 与 R1）都必须 bump build/version per AGENTS.md。本文档纯 docs，**不 bump**。
   - 建议下一次 patch-level 修复：`1.7.54 build 92`（如仅 R1）；`1.7.55 build 93`（如含 R2 + fork）；`1.8.0 build 94`（如同时升级 SwiftTerm 解决 Metal Toolchain）。

---

## 8. 风险与边界

- **SwiftTerm fork 风险**：R2 要 fork SwiftTerm 与本地 patch 维护成本。优先尝试 R1。
- **R1 layer.setNeedsDisplay() 性能风险**：iOS UIScrollView tile invalidation 每次重画整 surface，cell 数密 + scroll 频繁可能掉帧。需 throttle 到 ≥33ms。
- **CATransaction.setDisableActions(true)**：理论上 frame 赋值不在 UIView animation block 内本就不动 implicit anim；但保险加上不会 regress。
- **Diagnostic log 隐私**：禁止 log `sessionId`、relay pairing token、用户 input 明文；只 log hex8 / sha8 / 长度。
- **Bridge dedupe regression 风险**：R1/R2 都不改 Bridge，不会触发已有 `terminal-stream-hub.js` 测试 regression（之前 329/329 通过）。
- **不动方向**：feedPreservingScroll 的 1.5–2.0s 保留窗口、`isNearBottom()` 阈值、CR/LF normalization 都正确，不要改。
- **多 agent 协作隔离**：此文件命名带 agent 后缀（`-claude-opus-4.7`），独立保存结论；任何 cross-agent 综合应由 leader agent 单独 merge，避免 git race。

---

## 9. 直接答 §139 七问

1. **最高概率根因**：CaretView 独立 layer 与 TerminalView layer 在 Core Animation commit 阶段的 stale-tile-cache 残像（§3.1，~55%）。证据：buffer 正确、切 view 清掉、replay 清掉、ghost 在旧 cursor 位置、iOS-only。
2. **属于哪层**：SwiftTerm renderer / compositor 层（含 iOS-only path 的 `setNeedsDisplay(bounds)` TODO 与 CaretView layer commit 顺序），**不是** Bridge bytes/order，**不是** CaretView quarantine（quarantine 代码已无）。
3. **必须禁止的旧方案**：禁用 SwiftTerm、闪屏 replay 当终方案、`1.7.49/87` RunLoop drain、quarantine 重启、startup `replay:false`、盲升 SwiftTerm latest。理由：每一项已经在 1.7.x 历史里 regress 过具体功能（见 §4）。
4. **最小 diagnostic patch**：§5 D1（iOS instrument setNeedsDisplay/draw/addSubview CaretView，DEBUG-only NSLog）。文件 `SwiftTerminalCanvasView.swift` `MMSStreamTerminalView`。字段：bounds、contentOffset、contentSize、rect、CaretView frame。
5. **最小 real patch**：§6 R1（`feedPreservingScroll` 结尾 `self.layer.setNeedsDisplay()` + 33ms throttle）。文件 `SwiftTerminalCanvasView.swift` `MMSStreamTerminalView.feedPreservingScroll`。不动 Bridge、不动 SwiftTerm 源码、不闪屏。
6. **验证方式**：§7 三阶段（diagnostic → R1 → R2）；smoke 在 `song的iPhone`；命令 `idevicesyslog` 抓 `👻` log；R2 时 `npm test --prefix mms-remote-bridge`。不跑 Xcode tests。
7. **降级方案**：保持 SwiftTerm 启用，但提供**用户开关**（已在 UI 的 Terminal Settings 上增加一个 "Strict Cursor Redraw" toggle），开启后强制每次 echo 后 `layer.setNeedsDisplay()`（即 R1 行为，但用户可选关闭以恢复性能）。**绝不**禁用 SwiftTerm。

---

## 10. 给下一执行 agent 的建议

- 不要再增加 wrapper-level caret quarantine 代码（已确认非根因，且与现状 SwiftTerm 原生路径冲突）。
- 不要把这份文件与 `swiftterm-ghost-external-review.md` 合并；先收集所有并行 agent 的独立结论，再由 leader agent 合并 root-cause 概率分布。
- 实施 R1 前必须先跑 §5 D1 一次，落地 log 证据再写 patch；否则又回到"盲改"循环。
- iOS code 改动严格 bump build/version + 仅安装到 `song的iPhone`。
- 任何 Bridge 变动都要先跑 `npm test --prefix mms-remote-bridge`，因为 `tmux-control-adapter.test.js`/`terminal-stream-hub.test.js` 在 dirty working tree 已修改未提交，回归风险高。
