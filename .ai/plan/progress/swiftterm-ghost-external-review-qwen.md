# SwiftTerm Ghost 外部 Review — qwen3.6-plus

- **Timestamp**: 2026-05-16T23:55:00-04:00
- **Agent/Model**: qwen3.6-plus
- **Scope**: iOS SwiftTerm visual ghost/影子 after input
- **Status**: Research/docs-only, no code changes
- **Reviewed files**:
  - `AGENTS.md`, `.ai/plan/current.md`, `.ai/plan/progress/swiftterm-ghost-multiagent.md`
  - `.ai/plan/swiftterm-ghost-multiagent-prompt.md`
  - `Docs/swiftterm_ghost_analysis.md`
  - `SwiftTerminalCanvasView.swift` (full)
  - `SwiftTerminalHubView.swift` (full)
  - `AppleTerminalView.swift` (full, SwiftTerm checkout)
  - `iOSCaretView.swift` (full, SwiftTerm checkout)
  - `CaretView.swift` (full, SwiftTerm checkout)
  - `terminal-stream-hub.js`, `tmux-control-adapter.js`

---

## 背景

iOS `1.7.53 build 91` on `song的iPhone`. 空白启动 / `cd` 显示 / 乱码已修。剩余: SwiftTerm renderer 输入后视觉 ghost/影子，切换 tab 或刷新后消失。buffer 内容正确，纯视觉残留。

## 复现路径

1. 打开 SwiftTerm renderer tab
2. 输入字符（键盘 / 命令 + enter）
3. 观察: 输入位置附近出现字符形状 ghost
4. 切 tab 回来 / refresh → ghost 消失

## 已禁止方案

- 禁用 SwiftTerm
- replay/full-screen refresh 当最终修复
- `1.7.49/87` RunLoop/default-mode stream drain
- hidden input proxy + mobile cursor quarantine 当主修复
- 启动 stream 纯 `replay: false`
- 无条件升级 SwiftTerm latest（Metal Toolchain 问题未解）

---

## 独立代码审计

### A. `MMSStreamTerminalView` 现状

`SwiftTerminalCanvasView.swift:524-623`。包含:
- `feedPreservingScroll(_:)` — 保存 `contentOffset.y`, feed, 恢复
- `setContentOffset(_:animated:)` override — clamp X=0, 稳定手动滚动
- `layoutSubviews()` override — clamp X=0
- `applyTerminalFontIfNeeded(_)` — 避免重复设 font
- `disableSwiftTermAccessory()`
- `paste(_:)` override — bracketed paste

**关键观察**: 当前代码 **没有** `quarantineSwiftTermCaretViews()`, **没有** `addSubview(_:)` override, **没有** `draw(_:)` override, **没有** `flushDisplayAfterOutboundInput()`, **没有** `updateMobileCursorOverlay()`。Native SwiftTerm input/caret path 已完全恢复，所有 CaretView 交互走 SwiftTerm 原生路径。

### B. SwiftTerm `updateDisplay()` → `updateCursorPosition()` 链

`AppleTerminalView.swift:1455-1491`:
```swift
func updateDisplay(notifyAccessibility: Bool) {
    updateCursorPosition()  // line 1457 — 第一个调用
    // ...getUpdateRange...setNeedsDisplay(bounds)...
}
```

`AppleTerminalView.swift:1505-1531` (`updateCursorPosition`):
```swift
func updateCursorPosition() {
    guard let caretView else { return }
    let vy = buffer.yBase + buffer.y

    if vy >= buffer.yDisp + buffer.rows {
        caretView.removeFromSuperview()
        return
    } else if terminal.cursorHidden == false && caretView.superview != self {
        addSubview(caretView)  // ← 重新添加
    }
    // iOS lineOrigin
    let offset = (cellDimension.height * CGFloat(buffer.y + buffer.yBase))
    caretView.frame.origin = CGPoint(x: ..., y: lineOrigin.y)
    caretView.setText(ch: buffer.lines[vy][buffer.x])  // ← 渲染字符
}
```

### C. iOS `drawTerminalContents` 背景清除

`AppleTerminalView.swift:1026-1452`:
- iOS row 范围 (line 1037-1046): 用 `contentOffset.y` 计算 `firstRow/lastRow`
- 逐行 background fill (line 1166-1222): 只填充有 `backgroundColor` 属性的 segment rect
- **没有全局背景清除**。每行每个 segment 有 backgroundColor 时才 fill rect
- 空白/默认区域依赖 `UIScrollView.clearsContextBeforeDrawing`（默认 `true`）
- 尾部填补代码 (line 1391-1403) 被 `#elseif false` 包围，**iOS 不执行**

### D. CaretView `draw()` 渲染内容

`CaretView.swift` (iOS, `iOSCaretView.swift:124-132`):
```swift
override public func draw(_ dirtyRect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: 0, y: -frame.height)
    drawCursor(in: context, hasFocus: tracksFocus ? (superview?.isFirstResponder ?? true) : true)
}
```

`CaretView.swift` (`drawCursor`, line 12-67):
```swift
func drawCursor(in context: CGContext, hasFocus: Bool) {
    guard let ctline else { return }
    // clip + fill clear
    if !hasFocus {
        context.setStrokeColor(bgColor); context.setLineWidth(3); context.stroke(bounds); return
    }
    context.setFillColor(bgColor)
    // fill region (block/bar/underline)
    context.fill([region])

    // Only for block cursors: draw character glyph
    guard style == .steadyBlock || style == .blinkBlock else { return }
    let caretFG = caretTextColor ?? terminal.nativeForegroundColor
    context.setFillColor(caretFG.cgColor)
    for run in CTLineGetGlyphRuns(ctline) as? [CTRun] ?? [] {
        // CTFontDrawGlyphs — 渲染字符 glyph
    }
}
```

**关键发现**: block cursor 样式下，CaretView 不仅填充 cursor 区域背景色，还 **绘制字符 glyph**。这意味着当 `setText(ch:)` 传入的 `CharData` 对应一个可见字符时，CaretView 会把那个字符渲染到屏幕上。

### E. `feedPreservingScroll` 时序

`SwiftTerminalCanvasView.swift:544-559`:
```
T+0: layoutIfNeeded() + 保存 previousY
T+0: operation() → terminal.feed() → queuePendingDisplay() (16ms throttle)
T+0: layoutIfNeeded() + 恢复 contentOffset.y = restoredY
T+16ms: updateDisplay() → updateCursorPosition() → addSubview(caretView) + setText() → setNeedsDisplay(bounds)
T+~30ms: CoreAnimation commit → CaretView.draw() → drawCursor() → 字符 glyph 渲染
```

`feedPreservingScroll` 里所有操作在同一 runloop。`queuePendingDisplay` throttle 16ms 确保 display 在 feed+scroll-restore **之后**。

### F. Bridge 侧审计

`terminal-stream-hub.js`:
- `emitOutput` 用 monotonic seq，无重复 (line 164-181)
- `dropReplayMirroredPrefix` 防止 replay 后 live buffer 重复 (line 283-293)
- `replay` 期间 `isReplaying=true`, live output buffer 到 `replayBuffer` (line 169-172)

`tmux-control-adapter.js`:
- `normalizeTerminalOutputText` CR dedupe + LF→CR+LF (line 211-228)
- 无重复发送路径

**结论**: Bridge 侧无重复输出证据。Ghost 是视觉残留而非 buffer 重复。

---

## 根因排序

### H1 (最高概率 ~75%): `updateCursorPosition()` 每次 `updateDisplay()` 都执行 `addSubview(caretView)` + `setText()`，CaretView block cursor 渲染字符 glyph

**核心机制**:

1. `feed()` → `queuePendingDisplay()` throttle 16ms
2. 16ms 后 `updateDisplay()` → `updateCursorPosition()`
3. 如果 `cursorHidden == false && caretView.superview != self` → `addSubview(caretView)`
4. `setText(ch: buffer.lines[vy][buffer.x])` → 创建 CTLine (包含 cursor 位置的字符)
5. `setNeedsDisplay(bounds)` 触发 CaretView `draw()`
6. `drawCursor()` 在 block cursor 模式下渲染完整字符 glyph
7. CoreAnimation commit → GPU 呈现

**为什么 ghost 会残留而非被清除**:

CaretView 是 `TerminalView` 的 subview。`TerminalView` 的 `draw()` 调用 `drawTerminalContents()`，后者逐行绘制 buffer 内容。但 CaretView 作为独立 subview 有自己的 layer。当 `updateCursorPosition()` 更新 CaretView 的 `frame.origin` 到新的 cursor 位置时:

1. **旧位置**: CaretView 之前在某些位置渲染过 glyph。`frame.origin` 改变后，旧位置不再被 CaretView 覆盖。但 CaretView 的 layer 在 GPU 中的渲染数据可能尚未被 `TerminalView` 的下一帧内容覆盖（因为 `drawTerminalContents` 只绘制有 backgroundColor 的 segment，空白区域依赖 `clearsContextBeforeDrawing`）。

2. **新位置**: CaretView 在新位置渲染字符 glyph。这个 glyph 在 cursor 位置正常显示。

3. **残留**: 旧位置的 pixel data 如果不在 `TerminalView` 下一次 `draw()` 的 dirty rect 内，就不会被清除。`setNeedsDisplay(bounds)` 标记整个 bounds dirty，但 UIKit/CoreAnimation 会合并/裁剪 dirty rects，特别是 scroll view 的 tile-based rendering。

**与 `MMSStreamTerminalView` 的交互**: `feedPreservingScroll` 先 feed (可能触发 `updateScroller` 改变 `contentOffset`)，然后恢复 `contentOffset.y`。这导致 `UIScrollView` 的 backing store tile 布局在 feed 周期中发生变化。CoreAnimation 可能认为某些 tile 区域已经被 "valid" 内容覆盖，不触发重绘。

**为什么切换后消失**: Tab 切换 → SwiftUI `UIViewRepresentable` lifecycle → view 重建 → 全新 CALayer → 旧 backing store 丢弃 → 无残留。

**为什么 full redraw 能清**: `replayTerminalStream(reset: true)` → `resetToInitialState()` → `setNeedsDisplay(frame)` → 整个 frame 标记 dirty → 所有 tile 重绘 → 覆盖残留。

### H2 (~15%): `contentOffset.y` 与 `yDisp` 不一致导致 `drawTerminalContents` 绘制错误的 buffer row

**机制**: `feedPreservingScroll` 恢复 `contentOffset.y` 但不恢复 `terminal.displayBuffer.yDisp`。如果 SwiftTerm 内部 `updateScroller()` 在 feed 期间设置了 `yDisp`，而 `contentOffset` 被恢复到不同值，`drawTerminalContents` 用 `contentOffset.y` 计算的 `firstRow` 与 `yDisp` 不匹配，可能绘制 scrollback 行到 viewport 位置。

**反驳**: `queuePendingDisplay` 16ms throttle 确保 display 在 feed+restore 之后才触发。`updateScroller()` 在 `feedFinish()` 中被调用（在 `feedPreservingScroll` 内部），所以 yDisp 和 contentOffset 在 display 前都已经稳定。

### H3 (~7%): Background fill 不完整

`drawTerminalContents` 的背景填充 (line 1166-1222) 只填充有 backgroundColor 属性的 segment。空白区域（默认 attribute）没有显式 background fill。依赖 `UIScrollView.clearsContextBeforeDrawing` 清除。但 tile-based rendering 的 context clearing 可能在某些条件下不完整。

**反驳**: `clearsContextBeforeDrawing` 是 UIKit 基础机制，极少出 bug。更可能是 CaretView 的 layer 内容残留而非 TerminalView 的背景清除问题。

### H4 (~3%): Bridge byte/order 问题

已审计 `terminal-stream-hub.js` 和 `tmux-control-adapter.js`，无重复输出证据。Ghost 是视觉残留，buffer 内容正确。

---

## 与之前 agent 结论对比

### Peirce (dirty-rect / contentOffset 不一致)

**我的评估**: 部分正确，但不是主因。iOS path 已用 `contentOffset.y` 计算 firstRow/lastRow，不存在 dirtyRect 坐标问题。真正的 gap 是 **CaretView 作为 subview 的 layer 渲染 glyph 残留**，不是 TerminalView 自身的 dirty rect 计算。

### Kierkegaard (Bridge bytes/order)

**我的评估**: Bridge 侧代码审计确认无重复输出。Ghost 是 visual-only，buffer 正确。方向不对。

### 本文档 mimo-v2.5-pro (CaretView addSubview/setText)

**我的评估**: 根因判断与我一致（CaretView 是主要嫌疑）。但 mimo 给的 85% 概率略高 — 我认为 75% 更合理，因为 H2 (yDisp/contentOffset 错位) 仍需 diagnostic 验证。mimo 的 Patch 1（addSubview 拦截所有 CaretView）方案可行，但需要注意如果当前 cursor 样式是 block，拦截 CaretView 后需要确认自绘 cursor overlay 正常工作。

### 之前 docs Hypothesis 1 (quarantine race)

**我的评估**: 当前代码已无 quarantine 逻辑。Hypothesis 1 的时序分析仍然适用 — 只是之前尝试用 app-level quarantine 修复，而我现在认为更简洁的做法是在 `MMSStreamTerminalView` 层拦截 `addSubview`。

---

## 推荐 Diagnostic

### 1. 验证 H1 — CaretView 是否每次 feed 后都被 addSubview

在 `MMSStreamTerminalView` 加 `addSubview` override:

```swift
override func addSubview(_ view: UIView) {
    if String(describing: type(of: view)).contains("Caret") {
        print("🔴 CARET addSubview frame=\(view.frame) superview=\(view.superview)")
        Thread.callStackSymbols.prefix(8).forEach { print("  \($0)") }
    }
    super.addSubview(view)
}
```

输入字符后观察 console 是否出现 log + call stack 是否来自 `updateCursorPosition`。

### 2. 验证 H2 — yDisp vs contentOffset 对齐

在 `feedPreservingScroll` 加 log:

```swift
func feedPreservingScroll(_ operation: () -> Void) {
    let beforeYDisp = getTerminal().displayBuffer.yDisp
    layoutIfNeeded()
    let previousY = clampedVerticalOffset(contentOffset.y)
    let shouldRestore = maxVerticalOffset > 0 && !isNearBottom()

    isApplyingStreamFeed = true
    operation()
    isApplyingStreamFeed = false

    let afterYDisp = getTerminal().displayBuffer.yDisp

    if shouldRestore {
        layoutIfNeeded()
        let restoredY = clampedVerticalOffset(previousY)
        super.setContentOffset(CGPoint(x: 0, y: restoredY), animated: false)
    }

    let finalYDisp = getTerminal().displayBuffer.yDisp
    let finalOffset = contentOffset.y
    let expectedOffset = CGFloat(finalYDisp) * cellDimension.height
    let delta = abs(finalOffset - expectedOffset)

    print("🟡 yDisp: before=\(beforeYDisp) after=\(afterYDisp) final=\(finalYDisp)")
    print("🟡 offset: final=\(finalOffset) expected=\(expectedOffset) delta=\(delta)")
}
```

如果 `delta > cellHeight`，确认 yDisp/contentOffset 错位。

### 3. 对照实验

```bash
printf 'LONG-LINE-1234567890\r\033[Kshort\n'
printf 'LONG-LINE-1234567890\rshort\n'
```

对比有/无 `ESC[K` 的情况，区分 terminal clear 语义和 app ghost。

---

## 推荐 Patch

### Patch A（最小诊断，不改变行为）: addSubview log

见 Diagnostic #1。只加日志，不改变行为。确认/排除 H1。

### Patch B（最小修复，如果 H1 确认）: 拦截 CaretView addSubview

**文件**: `SwiftTerminalCanvasView.swift`, `MMSStreamTerminalView` class

```swift
override func addSubview(_ view: UIView) {
    // 阻止 SwiftTerm 的 CaretView 被重新添加到 view tree。
    // updateCursorPosition() 每次 display update 都可能 addSubview(caretView) + setText()，
    // 在 block cursor 模式下渲染字符 glyph，CoreAnimation commit 后残留为 ghost。
    if view is UIView, String(describing: type(of: view)).hasSuffix("CaretView") {
        return
    }
    super.addSubview(view)
}
```

**注意**: 如果 app 有自绘 `mobileCursorView`，拦截原生 CaretView 不影响 cursor 可见性。如果 app 没有自绘 cursor，拦截后 cursor 不显示 — 需先确认。

### Patch C（如果 H2 确认）: 同步 yDisp + contentOffset

**文件**: `SwiftTerminalCanvasView.swift`, `MMSStreamTerminalView.feedPreservingScroll`

在 restore contentOffset 前同步 yDisp:

```swift
if shouldRestore {
    let cellHeight = cellDimension.height
    if cellHeight > 0 {
        let targetYDisp = Int(round(clampedVerticalOffset(previousY) / cellHeight))
        let terminal = getTerminal()
        if terminal.displayBuffer.yDisp != targetYDisp {
            terminal.setViewYDisp(targetYDisp)
        }
    }
    layoutIfNeeded()
    let restoredY = clampedVerticalOffset(previousY)
    preservedScrollY = restoredY
    preserveScrollUntil = ProcessInfo.processInfo.systemUptime + 2.0
    super.setContentOffset(CGPoint(x: 0, y: restoredY), animated: false)
}
```

---

## 验证计划

1. 建 worktree，只加 diagnostic logs (Patch A)
2. `xcodebuild` debug build → 装到 `song的iPhone`
3. 手动 smoke: 输入字符，观察 console log
4. 根据 log 结果决定 Patch B 或 C
5. 修复后 bump build，安装验证

## Build/安装命令（仅在允许修复时）

```bash
cd /Users/xin/auto-skills/CtriXin-repo/mms-remote
git diff --check
HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test --prefix mms-remote-bridge
xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData-ghost-next CODE_SIGNING_ALLOWED=NO build
HOME=/Users/xin xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'id=00008150-0008781C36D9401C' -derivedDataPath .build/DerivedData-device build
xcrun devicectl device install app --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 .build/DerivedData-device/Build/Products/Debug-iphoneos/CodexMobile.app
```

---

## 风险

| 风险 | 级别 | 缓解 |
|------|------|------|
| 拦截 CaretView 后 cursor 不显示 | 中 | 确认是否有自绘 cursor overlay；如无，需实现替代方案 |
| 直接操作 yDisp 干扰 SwiftTerm 内部状态 | 低 | `setViewYDisp` 是 SwiftTerm 公开方法 |
| `setNeedsDisplay(frame)` 性能影响 | 中 | 只在 `isApplyingStreamFeed` 时触发，限制范围 |

---

## Web Research & Community Issues (第二轮)

### SwiftTerm 版本核验

Host 复核：`CodexMobile.xcodeproj` 和 `Package.resolved` 当前仍 pin **`9ad1b19`**。本轮外部 review 中提到的 `b1262db` 不应视为当前 app 实际依赖；后续分析以 project pin `9ad1b19` 为准。

### HEAD vs 我们的 AppleTerminalView 关键差异

| 特性 | 我们的 `9ad1b19` | HEAD `432a32d` |
|------|-----------------|---------------|
| DEC 2026 sync output debounce | **无** | `inSyncSequence` + `syncEndRenderTimer` + `syncSequenceSettleMs=100ms (iOS)` |
| `updateDisplay()` sync guard | **无** | `guard !terminal.synchronizedOutputActive && !inSyncSequence else { return }` |
| `updateCursorPosition()` | `addSubview(caretView)` + `setText(ch:)` | **完全相同逻辑**，无变化 |
| iOS `setNeedsDisplay` | `bounds`（coarse） | `bounds`（CG path）或 `metalView.setNeedsDisplay`（Metal path） |
| Metal renderer | 可选 | 新增 GPU backend (#484)，display-link 定时渲染 |
| cellDimension 像素对齐 | 无 | `snappedWidth/Height = ceil(value * scale) / scale` |
| `layoutSubviews` 后调用 | `setNeedsDisplay(bounds)` | 新增 `setNeedsDisplay(frame)` 强制全帧重绘 |
| `feedBegin/finish` 大小检查 | 直接 resize | 零大小 guard，避免 cols=rows=0 触发 resize |

### PR #498 (DEC 2026 sync output) — 对 ghost 的影响评估

**关键代码** (`iOSTerminalView.swift`):
```swift
var syncSequenceSettleMs: Int = 100  // iOS 默认 100ms
```

`synchronizedOutputChanged` 回调：
- BSU 到达 → `inSyncSequence = true` → 取消 pending render
- ESU 到达 → 启动 `syncEndRenderTimer`，100ms 后才触发 `updateScroller()` + `queuePendingDisplay()`
- `updateDisplay()` 开头 `guard !inSyncSequence else { return }` → sync 期间不渲染

**对 ghost 的影响**：
- PR #498 减少了 tmux sync 期间的 **中间 render 次数**，减少了 CaretView 被反复 addSubview 的机会
- **但最终 render 仍调用 `updateCursorPosition()` → `addSubview(caretView)` + `setText(ch:)`**
- PR #498 是 **放大因素修复**，不是根因修复。升级后 ghost 概率降低但仍存在
- 100ms debounce 意味着每次输入后 display 延迟 100ms 才触发（之前是 16ms）。这会让 ghost 出现频率降低，但单次 ghost 可能更持久（因为 render 间隔更长，旧 tile 更可能被覆盖前残留更久 — 这个方向不确定）

### 其他相关 PRs 对 ghost 的影响

| PR | 与 ghost 关系 |
|----|-------------|
| #531 fontSmoothing | macOS only，iOS 无关 |
| #527 duplicate accessibility | 修复重复方法调用，与 ghost 无关 |
| #499 force redraw on font change | 只影响字体切换场景 |
| #484 GPU backend | Metal renderer path，不影响 CG path |
| #289 caret renders glyph | 已合并（PR #289, 2023-04-17）。这是 ghost 视觉前提 |

### `updateCursorPosition()` 在 HEAD 中的状态

**完全未变**。我们的版本和 HEAD 版本的 `updateCursorPosition()` 代码一模一样：
```swift
func updateCursorPosition()
{
    guard let caretView else { return }
    let buffer = terminal.displayBuffer
    let vy = buffer.yBase + buffer.y
    if vy >= buffer.yDisp + buffer.rows {
        caretView.removeFromSuperview()
        return
    } else if terminal.cursorHidden == false && caretView.superview != self {
        addSubview(caretView)
    } else if terminal.cursorHidden == true && caretView.superview == self {
        caretView.removeFromSuperview()
    }
    // ...frame.origin + setText(ch:)...
}
```

`addSubview(caretView)` + `setText(ch:)` 逻辑在 SwiftTerm HEAD **仍然存在**，没有任何社区修复。

### 结论

1. **升级 SwiftTerm 到 HEAD 不能直接修复 ghost**。`updateCursorPosition` 的 CaretView addSubview/setText 逻辑完全未变
2. PR #498 是有益的补充（减少中间 render 次数），但不是替代品
3. **App-level 修复（Patch B: addSubview 拦截）仍是唯一能直接阻断根因的方案**
4. SwiftTerm 升级的好处：PR #498（sync debounce）+ cellDimension 像素对齐 + 零大小 guard + VoiceOver 支持 + 各种 bug 修复
5. 升级障碍：Metal renderer 需要 Metal Toolchain，但 **iOS CG path 不受影响**（CG path 是独立的，`#if canImport(MetalKit)` 在 iOS 上默认不走 Metal 除非 app 显式启用）。升级后只要不启用 Metal，CG path 应该正常工作

**最可能根因 (75%)**: SwiftTerm `updateCursorPosition()` 在 `updateDisplay()` 周期中 `addSubview(caretView)` + `setText()`，block cursor 模式下渲染完整字符 glyph。CaretView layer 在 CoreAnimation commit 后，旧位置 pixel data 未被 `TerminalView` 的下一帧内容覆盖 → ghost 残留。

**次要可能 (15%)**: `feedPreservingScroll` 恢复 `contentOffset.y` 但不恢复 `yDisp`，导致 `drawTerminalContents` row 计算错位。

**第二轮 web research 结论**: SwiftTerm HEAD 的 `updateCursorPosition()` 与我们的版本**完全相同** — `addSubview(caretView)` + `setText(ch:)` 未被任何社区 PR 修复。升级 SwiftTerm 到 HEAD 不能直接修复 ghost，但 PR #498 (DEC 2026 sync output debounce, iOS `syncSequenceSettleMs=100ms`) 能减少中间 render 次数，作为 defense-in-depth。

**推荐**: 先加 diagnostic logs 验证 H1/H2，确认后 Patch B（拦截 CaretView addSubview）作为最小修复。建议组合 Patch B + 未来升级 SwiftTerm 到 HEAD（只走 CG path，不启用 Metal）。两个 patch 都是 iOS wrapper 层最小变更，不涉及 SwiftTerm 源码 fork。
