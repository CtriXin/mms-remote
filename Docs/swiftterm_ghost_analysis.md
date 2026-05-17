# SwiftTerm Ghost/Double Character 根因分析


## 2026-05-16T23:21:34-04:00 Multiagent Results — recorded, no blind patch

User confirmed after `1.7.53 build 91`: other regressions are fixed, but SwiftTerm visual ghost/影子 still remains. We stopped local trial-and-error and asked two agents.

### Peirce — SwiftTerm renderer/caret source

Conclusion: most likely root is SwiftTerm iOS renderer dirty-rect/background clear interacting with `UIScrollView.contentOffset`; `CaretView` can amplify the artifact but wrapper-level hidden input / quarantine is not a root fix.

Evidence highlights:
- `AppleTerminalView.swift` clears with `dirtyRect` but draws rows using `contentOffset`, so iOS scroll/dirty coordinates can diverge.
- SwiftTerm source already has an iOS dirtyRect/scroll TODO around row selection; that does not fully address background clearing.
- `updateDisplay()` updates cursor and then redraws, so input echo can interleave cursor glyph and redraw transactions.

Patch direction:
- SwiftTerm source-level draw fix: on iOS clear `visibleRect = CGRect(x: 0, y: contentOffset.y, width: bounds.width, height: bounds.height)` or clear each visible row before drawing.
- Cursor fix: invalidate old/new caret frame union; consider bar/underline cursor without glyph fill if needed.
- App wrapper: only preserve scroll offset when user manually scrolled; after restoring offset, invalidate visible rect.

### Kierkegaard — Bridge/tmux/feed race

Conclusion: Bridge is less likely than renderer for the visual-only symptom, but still has replay/live/input ordering risks that should be measured before ruling out.

Evidence highlights:
- Viewport replay is reconstructed text from `tmux capture-pane`, not raw terminal state; appending final CRLF can move SwiftTerm cursor state.
- Live-during-replay buffering uses text heuristic and can miss ANSI/partial overlap.
- iOS input sends use independent async tasks; bracketed paste or split input could reorder without a per-pane input queue.

Diagnostic direction:
- Temporary trace: streamId suffix, paneId, seq, type, replay flag/phase, byte length, sha256, first/last hex, buffer/drop counters at Bridge emit/replay/flush and iOS feed.
- Repro cases: `printf 'LONG-LINE-1234567890\r\033[Kshort\n'` versus no `ESC[K` to separate terminal clear semantics from app ghost.

### Combined decision

Do not continue replay/full-refresh/caret-wrapper guesses. If this bug gets another pass, start with source-level SwiftTerm draw invalidation plus narrow Bridge/iOS byte-order telemetry. Otherwise park as known unresolved and continue v2 work.


## 2026-05-16 Escalation Update — still unresolved after 1.7.53/91

Current device point: `1.7.53 build 91` installed and launched on `song的iPhone`. User confirms blank startup / `cd` display /乱码 regressions are fixed, but SwiftTerm visual ghost/影子 still remains. Treat this as unresolved root-cause work; stop local trial-and-error.

Important negative evidence:
- Startup live-only (`replay: false`) caused blank/empty terminal; fixed by restoring startup viewport replay only.
- Full replay/full redraw clears ghost but flashes; not acceptable as final fix.
- RunLoop/default-mode stream drain from `1.7.49/87` worsened `cd`/`pwd` echo/order; do not retry.
- Hidden input proxy + mobile cursor overlay + CaretView quarantine/addSubview interception did not eliminate ghost; likely wrong or incomplete direction.
- Bridge CR/LF normalization and viewport replay cleanup fixed garble/blank symptoms but did not fix ghost.
- SwiftTerm latest `602be53` currently fails generic iOS build because local Xcode lacks Metal Toolchain; do not upgrade without addressing that.

Current hypothesis status:
- CaretView may still be involved, but app-level quarantine wrappers failed; next attempt should use SwiftTerm source-level evidence/patch, not wrapper timing.
- Renderer dirty rect / UIScrollView/CoreAnimation compositing remains plausible because switching/refreshing clears the visual artifact while buffer content is correct.
- Bridge byte/order race is less likely after CR/LF normalization and user-confirmed functional output, but still needs one focused evidence check before ruling out.

Escalation packet: `.ai/plan/swiftterm-ghost-multiagent-prompt.md`. Two read-only explorer agents were started: `Peirce` for SwiftTerm renderer/caret source, `Kierkegaard` for Bridge/tmux/feed race.

## 问题概述

iOS Terminal (SwiftTerm renderer) 在用户输入后出现 "双字符/影子/ghost" 视觉残留：
- 不是实际内容重复（buffer 是对的）
- 切换出去再回来 → 消失
- 输入后出现
- replay/full-redraw 能清掉，但会"闪一下"

---

## Top 3 Root-Cause Hypotheses（按概率排序）

### 🥇 Hypothesis 1: CaretView `setText()` 在 quarantine race 中留下 stale glyph（概率 ~70%）

#### 机制

1. 用户按键 → `inputProxy.insertText` → `Coordinator.inputProxy(_:didCommitText:)` → `sendInputData()` → `flushDisplayAfterOutboundInput()`
2. 同时，Bridge 收到输入后 echo 回 output → `feed(byteArray:)` → SwiftTerm 内部 `queuePendingDisplay()` → 16ms 后 `updateDisplay()` → **`updateCursorPosition()`**
3. `updateCursorPosition()` 中关键行为（[AppleTerminalView.swift:1368-1382](file:///Users/xin/auto-skills/CtriXin-repo/mms-remote/.build/DerivedData-swift-tab-build/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift#L1357-L1383)）：

```swift
// 如果 cursor 不隐藏且 caretView 不在 superview，重新 addSubview
} else if terminal.cursorHidden == false && caretView.superview != self {
    addSubview(caretView)  // ← 关键：quarantine 后被重新加回来
}

// 设置位置和字形
caretView.frame.origin = CGPoint(x: ..., y: ...)
caretView.setText(ch: buffer.lines[vy][buffer.x])  // ← 渲染字符到 CaretView
```

4. `setText()` 在 [iOSCaretView.swift:80-87](file:///Users/xin/auto-skills/CtriXin-repo/mms-remote/.build/DerivedData-swift-tab-build/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift#L80-L87) 中创建 `CTLine` 并 `setNeedsDisplay(bounds)` — 这会让 CaretView 在其 `draw(_:)` 中 **渲染 cursor 位置的字符 glyph**

5. `MMSStreamTerminalView` 的 quarantine 逻辑在 [SwiftTerminalCanvasView.swift:1116-1139](file:///Users/xin/auto-skills/CtriXin-repo/mms-remote/CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift#L1116-L1139) 中调用 `quarantineSwiftTermCaretViews()` — 将 CaretView 隐藏、移出屏幕、removeFromSuperview

6. **Race condition**：
   - `queuePendingDisplay()` 的 16ms throttle 定时器在 `DispatchQueue.main.asyncAfter` 中
   - `flushDisplayAfterOutboundInput()` 在同步路径中
   - `schedulePostStreamCursorRefresh()` 分别在 20ms / 60ms / 140ms 后调度
   - 但 `updateCursorPosition()` 在 SwiftTerm 自己的 `updateDisplay()` 中也被调用

   **时序**：
   ```
   T+0ms:   inputProxy.insertText → flushDisplayAfterOutboundInput() → quarantine caret
   T+16ms:  SwiftTerm queuePendingDisplay fires → updateDisplay() → updateCursorPosition()
            → addSubview(caretView) ← 重新加回来！
            → caretView.setText() → CTLine 绘制字符 glyph
            → caretView.setNeedsDisplay() → draw() renders glyph at cursor position
   T+30ms:  flushDisplayAfterOutboundInput 的第一个延迟 quarantine 再次 hide
            但此时 caretView 的 layer 已经 committed → GPU 留下 stale glyph
   ```

   **CaretView 的 `draw()` 会绘制的内容**（[iOSCaretView.swift:124-132](file:///Users/xin/auto-skills/CtriXin-repo/mms-remote/.build/DerivedData-swift-tab-build/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/iOS/iOSCaretView.swift#L124-L132)）：
   ```swift
   override public func draw(_ dirtyRect: CGRect) {
       guard let context = UIGraphicsGetCurrentContext() else { return }
       context.scaleBy(x: 1, y: -1)
       context.translateBy(x: 0, y: -frame.height)
       drawCursor(in: context, hasFocus: tracksFocus ? (superview?.isFirstResponder ?? true) : true)
   }
   ```
   注意 `hasFocus` 判断：由于 `tracksFocus` 被设为 `false`，所以 `hasFocus` 永远为 `true`，意味着 **即使 CaretView 被 quarantine 之前瞬间显示过，它也会用 filled/block 样式绘制字符 glyph**。

#### 证据

| 证据 | 说明 |
|------|------|
| ✅ "输入后出现" | 正是 input → echo → `updateDisplay()` → `updateCursorPosition()` → `addSubview(caretView)` 的时序 |
| ✅ "切换出去再回来消失" | Tab 切换触发 `makeUIView` / `updateUIView` 重建，caretView 被 fresh quarantine，旧 stale layer 被丢弃 |
| ✅ "replay/full-redraw 能清" | `forceFullViewportRedraw()` 先 quarantine 然后 `layer.setNeedsDisplay()` → 重新绘制整个 bounds 覆盖 stale glyph |
| ✅ ghost 是字符形状 | `setText()` 的 `CTLine` 渲染出完整字符，不只是 cursor bar |
| ✅ 位于 cursor 位置 | `updateCursorPosition()` 设置的 `frame.origin` 就是当前 cursor 的 buffer 坐标 |

#### 反证

| 可能反证 | 回应 |
|----------|------|
| "已经设了 `caretViewTracksFocus = false`" | 这反而让 `draw()` 始终以 hasFocus=true 渲染 filled cursor（带字符 glyph），使问题更严重 |
| "quarantine 调用了 `removeFromSuperview()`" | 但 `updateCursorPosition()` 中 `addSubview(caretView)` 会把它加回来 |

---

### 🥈 Hypothesis 2: `updateDisplay()` 的 iOS `setNeedsDisplay(bounds)` 未正确清除旧 glyph 区域（概率 ~20%）

#### 机制

在 [AppleTerminalView.swift:1339-1343](file:///Users/xin/auto-skills/CtriXin-repo/mms-remote/.build/DerivedData-swift-tab-build/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift#L1339-L1343)：

```swift
#else
// TODO iOS: need to update the code above, but will do that when I get some real
// life data being fed into it.
setNeedsDisplay(bounds)
#endif
```

macOS 用 dirty-rect 精确重绘，但 **iOS 直接 `setNeedsDisplay(bounds)`**。这本身应该触发全屏重绘——但问题是 `UIScrollView` 的 `draw(_:)` 只在 **可见 viewport** 区域被 Core Animation 调度：

- `TerminalView` 继承自 `UIScrollView`
- `UIScrollView` 的 tile-based rendering 可能不会重绘 cursor 移动后留下的旧位置
- 尤其是当 `contentOffset` 没变但 cursor 从位置 A 移动到位置 B 时，位置 A 的 stale glyph 可能不在新 dirty rect 中

但这更像是一个 **辅助因素** 而不是根因，因为 iOS 的 `setNeedsDisplay(bounds)` 理论上应该覆盖整个可见区域。

#### 证据

- SwiftTerm 源码中有明确 TODO 注释说 iOS path 需要改进
- ghost 出现在 cursor 之前的位置（cursor 移动后旧位置残留）

#### 反证

- `setNeedsDisplay(bounds)` 应该标记整个 bounds 为 dirty，UIKit 应该重绘

---

### 🥉 Hypothesis 3: `MMSStreamTerminalView.feedPreservingScroll` 中的 scroll offset 保持干扰了 dirty rect 计算（概率 ~10%）

在 [SwiftTerminalCanvasView.swift:1032-1050](file:///Users/xin/auto-skills/CtriXin-repo/mms-remote/CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift#L1032-L1050)，`feedPreservingScroll` 会在 feed 后恢复 `contentOffset`。SwiftTerm 内部的 `updateScroller()` 会设置 `contentOffset` 到底部，但 `feedPreservingScroll` 覆盖了这个。这可能导致 `setNeedsDisplay(bounds)` 标记的 rect 与实际显示的 viewport 不一致。

#### 证据

- 当用户 scroll 到中间然后输入时更容易出现 ghost
- `setContentOffset` 的 override 可能使 UIKit 的 display cycle 跳过某些 tile

#### 反证

- 如果用户始终在底部，仍然出现 ghost → 这不是唯一原因

---

## 关键问题回答

### Q1: 为什么"切换出去再回来消失"？

Tab 切换 → SwiftUI 的 `UIViewRepresentable` lifecycle → `updateUIView` 不会重建整个 view，但 SwiftUI 会 **重新 layout** → `layoutSubviews()` 触发 → `forceFullViewportRedraw()` → quarantine caretViews + 全屏 `setNeedsDisplay` → **stale layer 被覆盖**。

另外如果是完全离开 view 再回来，`makeUIView` 重新创建容器，旧 caretView 连同其 stale layer 被释放。

### Q2: 为什么"输入后出现"？

输入 → `onSendData` → Bridge → echo back → `feed(byteArray:)` → SwiftTerm `queuePendingDisplay()` → 16ms 后 `updateDisplay()` → `updateCursorPosition()` **re-adds caretView + 绘制字符 glyph** → quarantine 来不及清除或 quarantine 后 layer commit 已经完成。

### Q3: 为什么 replay/full-redraw 能清，但会闪？

`replayTerminalStream()` → Bridge 发送 `replayStart(reset: true)` → `reset(terminalView)` → `resetToInitialState()` **清空整个 buffer** → 黑屏（闪的来源）→ 然后重新 feed 所有 capture-pane output → 画面恢复。

这是一个 **scorched-earth** 策略，闪屏不可避免因为 buffer 被清空了。

### Q4: 应该如何做真正低闪/无闪修复？

见下方修复方案。

---

## 推荐修复方案

### 方案核心：在 `MMSStreamTerminalView` 中拦截 `updateCursorPosition()` 防止 caretView 被重新添加

这是 **最小侵入、无闪烁** 的修复。

### 具体 Patch

#### Patch 1：Override `updateCursorPosition()` — 阻止 CaretView 回归

**文件**: [SwiftTerminalCanvasView.swift](file:///Users/xin/auto-skills/CtriXin-repo/mms-remote/CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift)

在 `MMSStreamTerminalView` class 中（line 940 附近），添加：

```swift
// ── 核心修复：阻止 SwiftTerm 的 updateCursorPosition()
//    重新 addSubview(caretView) ──

/// 拦截 SwiftTerm 内部的 cursor 更新。
/// 原始实现会在 cursor 不隐藏且 caretView 不在 superview 时 addSubview(caretView)，
/// 导致 quarantine 失效，CTLine 渲染的字符 glyph 残留成 ghost。
/// 我们替换为：只更新 mobileCursorView 位置，永远不恢复原生 caretView。
override func updateCursorPosition() {
    // 不调用 super.updateCursorPosition()
    // 只更新自绘的 mobileCursorView
    quarantineSwiftTermCaretViews()
    updateMobileCursorOverlay()
}
```

> [!WARNING]
> `updateCursorPosition()` 是 `internal` 方法，不是 `open/public`。需要确认 SwiftTerm 的 access control。

#### Patch 1-alt：如果 `updateCursorPosition()` 无法 override

**文件**: [SwiftTerminalCanvasView.swift](file:///Users/xin/auto-skills/CtriXin-repo/mms-remote/CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift)

在 `MMSStreamTerminalView` 中 override `addSubview(_:)` 的现有实现（line 957），**加强 quarantine** 逻辑使其包含对 `caretView` 属性的 nil 化：

```swift
override func addSubview(_ view: UIView) {
    if isSwiftTermCaretView(view) {
        quarantineSwiftTermCaretView(view)
        return  // ← 关键：直接 return，不调用 super.addSubview
    }
    super.addSubview(view)
}
```

当前代码是：
```swift
override func addSubview(_ view: UIView) {
    super.addSubview(view)  // ← 先加了才 quarantine，glyph 可能已经 committed
    if isSwiftTermCaretView(view) {
        quarantineSwiftTermCaretView(view)
    }
}
```

**这个修改更简单且必须做：先检查再 add，不要先 add 再 quarantine。**

#### Patch 2：防止 `draw(_:)` 中 caretView 的 stale 渲染

**文件**: [SwiftTerminalCanvasView.swift](file:///Users/xin/auto-skills/CtriXin-repo/mms-remote/CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift)

在 `MMSStreamTerminalView.draw(_:)` override 中，确保 quarantine 先于 draw：

```swift
override public func draw(_ dirtyRect: CGRect) {
    quarantineSwiftTermCaretViews()  // ← 在 draw 前再次确保 caretView 被清除
    super.draw(dirtyRect)
    // 如果 super.draw 中 updateCursorPosition() 再次 add caretView，
    // 这里会在下一帧被 quarantine 清除
}
```

#### Patch 3：`flushDisplayAfterOutboundInput()` 改进

**文件**: [SwiftTerminalCanvasView.swift](file:///Users/xin/auto-skills/CtriXin-repo/mms-remote/CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift)

当前实现在 line 1010-1021：

```swift
func flushDisplayAfterOutboundInput() {
    quarantineSwiftTermCaretViews()
    updateMobileCursorOverlay()
    redrawLastMobileCursorFrame()
    for delay in [0.03, 0.10] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.quarantineSwiftTermCaretViews()
            self?.updateMobileCursorOverlay()
            self?.redrawLastMobileCursorFrame()
        }
    }
}
```

需要 **添加 16ms 时间点**（与 SwiftTerm 的 `queuePendingDisplay` fps60 throttle 对齐），并在 cursor 区域执行精确 invalidation：

```swift
func flushDisplayAfterOutboundInput() {
    quarantineSwiftTermCaretViews()
    updateMobileCursorOverlay()
    redrawLastMobileCursorFrame()
    // 与 SwiftTerm 的 queuePendingDisplay 16ms throttle 对齐
    for delay in [0.018, 0.035, 0.10] {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.quarantineSwiftTermCaretViews()
            self?.updateMobileCursorOverlay()
            self?.redrawLastMobileCursorFrame()
        }
    }
}
```

---

## 最小验证办法（不跑 Xcode tests）

### 验证 Hypothesis 1

1. **在 `MMSStreamTerminalView.addSubview` 中加 print log**：

```swift
override func addSubview(_ view: UIView) {
    if isSwiftTermCaretView(view) {
        print("🔴 GHOST DEBUG: CaretView being re-added! frame=\(view.frame)")
        Thread.callStackSymbols.prefix(8).forEach { print("  \($0)") }
        quarantineSwiftTermCaretView(view)
        return
    }
    super.addSubview(view)
}
```

2. 在 Simulator 中输入几个字符，观察 console 是否出现 `🔴 GHOST DEBUG: CaretView being re-added!` 以及 call stack 是否来自 `updateCursorPosition()`。

3. 如果能看到 `updateCursorPosition` → `addSubview(caretView)` 的 call stack，则确认根因。

### 验证 Hypothesis 2

在 `MMSStreamTerminalView` 中 override `draw(_:)` 并 log dirty rect：

```swift
override public func draw(_ dirtyRect: CGRect) {
    print("🟡 DRAW dirtyRect=\(dirtyRect) bounds=\(bounds) contentOffset=\(contentOffset)")
    super.draw(dirtyRect)
}
```

观察 `dirtyRect` 是否完整覆盖 viewport。

---

## 修复优先级

```
┌─────────────────────────────────────────────────────┐
│ 1. Patch 1-alt: addSubview 先检查后 add（必做）      │ ← 最关键
│ 2. Patch 3: flushDisplayAfterOutboundInput 增加 18ms │ ← 辅助
│ 3. Patch 2: draw override 中预先 quarantine          │ ← 保险
│ 4. Patch 1: override updateCursorPosition（如可行）  │ ← 最彻底
└─────────────────────────────────────────────────────┘
```

## 不需要改的

- ❌ 不需要修改 Bridge 侧（`terminal-stream-hub.js` 的 dedupe 逻辑已正确）
- ❌ 不需要修改 `CodexService+Terminal.swift`（stream event handling 无 duplicate）
- ❌ 不需要 `replaysSwiftTermAfterInput`（已正确设为 `false`）
- ❌ 不需要动 hidden input proxy `MMSStreamInputProxyTextView` 逻辑
- ❌ 不需要 resize churn fix（不是此 bug 的原因）

## Version Bump

修复后需要 bump build number，per AGENTS.md build guardrail：
- 这是 patch-level fix → `1.7.44` build `83`
- 修改 Xcode project 中 `MARKETING_VERSION` 保持 `1.7.44`，`CURRENT_PROJECT_VERSION` → `83`


---

## 2026-05-16 External Review — deepseek-v4-flash

Agent: deepseek-v4-flash
Model: deepseek-v4-flash
Scope: research/docs-only, no code changes
Status: analysis-complete

### Key Finding: Quarantine Code Does NOT Exist In Current Codebase

Prior agents analyzed quarantine logic at lines 957/1116-1139. **These lines do not exist in `1.7.53 build 91`.** `MMSStreamTerminalView` (SwiftTerminalCanvasView.swift:524-623) has zero quarantine methods, zero `addSubview` override, zero `draw` override. Ghost persists without any app-level quarantine race.

### Access Control Constraint (Missed By All Prior Agents)

`CaretView` class is `internal` to SwiftTerm module (`class CaretView: UIView`, no `public`). `caretView` property on `TerminalView` is also `internal`. This means the `view === caretView` comparison proposed by mimo-v2.5-pro will NOT compile from `CodexMobile` app module. Workaround: string-based type check via `String(describing: type(of: view)) == "CaretView"` or `NSClassFromString("SwiftTerm.CaretView")`.

### Root Cause Assessment

**H1 (~60%) — CaretView glyph overlay:** `updateCursorPosition()` calls `caretView.setText(ch:)` every `updateDisplay()` cycle. `setText()` creates CTLine + `setNeedsDisplay(bounds)`. `CaretView.drawCursor()` fills block cursor and renders character glyph via `CTFontDrawGlyphs` on top of terminal buffer. The overlay creates "double character" visual. When `tracksFocus = true` (default), only renders filled block when `isFirstResponder`. Ghost worst during active input.

**H2 (~25%) — iOS `updateCursorPosition()` coordinate mismatch:** iOS uses absolute `buffer.y + buffer.yBase` for CaretView position, not viewport-relative coordinates. `feedPreservingScroll()` restores `contentOffset` after feed, but `updateCursorPosition()` computed CaretView position before offset restoration. Display cycle commits at stale visual position.

**H3 (~10%) — Bridge replay CRLF:** Unconditional `\r\n` append in viewport replay may push cursor. Minor factor.

**H4 (~5%) — dirty-rect (Peirce hypothesis):** Already mitigated — iOS uses `contentOffset.y` and `setNeedsDisplay(bounds)`.

### Recommended Patch

1. **Primary: Intercept CaretView in `addSubview`** — return without calling super when `String(describing: type(of: view)) == "CaretView"`
2. **Defensive: `setContentOffset` override** with `setNeedsDisplay()` for old CaretView rect
3. **Bridge: Conditional trailing CRLF** in viewport replay

### Web Research — Community Issues & Alternatives

**No existing community solution for this specific ghost.** SwiftTerm maintainer acknowledges iOS UIScrollView cursor positioning is broken ([#133](https://github.com/migueldeicaza/SwiftTerm/issues/133)) — "cursor position is off... not aware of new approach at being positioned in screen". Describes "garbage left behind" — same ghost pattern.

Key related issues:
- [#227](https://github.com/migueldeicaza/SwiftTerm/issues/227): CJK/emoji double-width cursor misalignment. Cursor size not computed from glyph runs. Space appended after double-width chars creates visual artifacts.
- [#342](https://github.com/migueldeicaza/SwiftTerm/issues/342): `setCursorColor()` broken. CaretView.drawCursor uses `bgColor` not `caretColor`. Shows CaretView rendering is under-maintained.
- [#244](https://github.com/migueldeicaza/SwiftTerm/issues/244): CaretView stale position on layout change. macOS, but same stale-position pattern.
- [CodeEdit PR #1117](https://github.com/CodeEditApp/CodeEdit/pull/1117): SwiftTerm 1.2.0 cursor fixes but we're blocked by Metal Toolchain.

**Alternatives evaluated:**
- `clipsToBounds = true`: already set, doesn't stop glyph overlay
- `updateDisplay()` after every addSubview: already happens, doesn't prevent stale glyph
- Remove/re-add CaretView: same as quarantine, updateCursorPosition re-adds it
- Cursor style bar/underline: reduces glyph area but CTFontDrawGlyphs still renders
- SwiftTerm 1.2.0 upgrade: blocked. No guarantee fixes iOS CaretView compositing

**Verdict: addSubview interception remains optimal fix.** No community workaround exists. CaretView addSubview/setText/drawCursor path is SwiftTerm internal behavior with no public API to control it.

### Full Report

`.ai/plan/progress/swiftterm-ghost-deepseek-v4-flash.md`

## 2026-05-16T23:55:00-04:00 Independent External Review — mimo-v2.5-pro

Agent/Model: mimo-v2.5-pro
Scope: research/docs-only, no code changes
Status: analysis-complete

### 结论

**最高概率根因 (85%)：SwiftTerm `updateCursorPosition()` 在每次 `updateDisplay()` 周期中无条件调用 `addSubview(caretView)` + `setText()`，CaretView 的 `drawCursor()` 渲染完整字符 glyph 到 layer，CoreAnimation 提交后 GPU 残留为 ghost。**

### 关键源码证据

1. `AppleTerminalView.swift:1516-1517` — `else if terminal.cursorHidden == false && caretView.superview != self { addSubview(caretView) }`
2. `AppleTerminalView.swift:1457` — `updateDisplay()` 第一行就调用 `updateCursorPosition()`
3. `AppleTerminalView.swift:1548-1560` — `queuePendingDisplay()` 16ms throttle，`asyncAfter` 调用 `updateDisplay()`
4. `iOSCaretView.swift:80-87` — `setText()` 创建 CTLine + `setNeedsDisplay(bounds)`
5. `CaretView.swift:31-65` — `drawCursor()` steadyBlock 模式填充 bounds + `CTFontDrawGlyphs` 绘制字符
6. `SwiftTerminalCanvasView.swift:524-623` — 当前 `MMSStreamTerminalView` **没有** override `addSubview()` 或 `updateCursorPosition()`，**没有** quarantine 逻辑

### 与之前 agent 结论对比

- **Peirce (dirty-rect/contentOffset 不一致)**：概率低。iOS path 已用 `contentOffset.y` 计算 firstRow/lastRow（line 1045-1046），不依赖 `dirtyRect`；且用 `setNeedsDisplay(bounds)` 标记全 bounds dirty。
- **Kierkegaard (Bridge bytes/order)**：概率低 (~5%)。ghost 是 visual-only，buffer 内容正确；CR/LF normalization 已正确实现。
- **Docs 中原有 Hypothesis 1 (CaretView quarantine race)**：方向正确。但当前代码中 quarantine 逻辑已被移除，说明之前的 quarantine 实现（先 addSubview 再 quarantine）不够彻底。

### 推荐 Patch

**核心 Patch（必做）**：在 `MMSStreamTerminalView` 中 override `addSubview()`，拦截 CaretView：

```swift
override func addSubview(_ view: UIView) {
    if let caretView = (self as? TerminalView)?.caretView, view === caretView {
        return  // 阻止 CaretView 加入 view tree，避免 drawCursor 渲染字符 glyph
    }
    super.addSubview(view)
}
```

**原理**：CaretView 不在 view tree → `setNeedsDisplay()` 不触发 draw → 无 glyph 渲染 → 无 ghost。app 有自绘 `mobileCursorView` 替代 cursor 显示。

### 详细分析

完整分析见 `.ai/plan/progress/swiftterm-ghost-external-review.md`。

## 2026-05-16T23:55:00-04:00 Independent External Review — qwen3.6-plus

Agent/Model: qwen3.6-plus
Scope: research/docs-only, no code changes
Status: analysis-complete

### 结论

**最高概率根因 (~75%)：SwiftTerm `updateCursorPosition()` 在每次 `updateDisplay()` 周期中 `addSubview(caretView)` + `setText(ch:)`。Block cursor 模式下渲染完整字符 glyph。CaretView layer 在 CoreAnimation commit 后，旧位置 pixel data 未被 `TerminalView` 下一帧内容覆盖 → ghost 残留。**

**次要可能 (~15%)：`feedPreservingScroll` 恢复 `contentOffset.y` 但不恢复 `terminal.displayBuffer.yDisp`，导致 `drawTerminalContents` 的 `firstRow` 计算与实际 `yDisp` 不匹配。**

### 独立源码审计要点

1. `AppleTerminalView.swift:1457` — `updateDisplay()` 第一行调用 `updateCursorPosition()`
2. `AppleTerminalView.swift:1505-1531` — `updateCursorPosition()` 条件 `addSubview(caretView)` + `setText(ch:)` + `frame.origin` 设置
3. `CaretView.swift:31-67` — `drawCursor()` block 模式渲染完整字符 glyph (`CTFontDrawGlyphs`)
4. `iOSCaretView.swift:124-132` — `draw()` 调用 `drawCursor(in:hasFocus:)`，`tracksFocus=false` 时 `hasFocus` 永远 `true`
5. `SwiftTerminalCanvasView.swift:524-623` — `MMSStreamTerminalView` 当前无 CaretView 拦截、无 quarantine、无 `addSubview` override
6. `AppleTerminalView.swift:1166-1222` — 背景填充只对有 backgroundColor 的 segment 生效，空白区域依赖 `clearsContextBeforeDrawing`
7. `AppleTerminalView.swift:1391-1403` — iOS 尾部填补被 `#elseif false` 禁用

### Bridge 侧结论

`terminal-stream-hub.js` / `tmux-control-adapter.js` 全量审计确认无重复输出路径。Ghost 是 visual-only，buffer 内容正确。Bridge 不是根因。

### 与之前 agent 对比

- **Peirce (dirty-rect / contentOffset)**：iOS path 已用 `contentOffset.y` 计算 firstRow/lastRow，不依赖 `dirtyRect`。真正的 gap 是 CaretView layer glyph 残留，不是 TerminalView dirty rect 计算。
- **Kierkegaard (Bridge bytes/order)**：不对。Bridge 侧无重复输出证据。
- **mimo-v2.5-pro (CaretView addSubview/setText)**：根因判断一致。mimo 给 85%，我估 75% 更合理（H2 yDisp/contentOffset 错位仍需 diagnostic 验证）。
- **deepseek-v4-flash (access control constraint)**：正确指出 `CaretView` 是 `internal`，`view === caretView` 可能跨模块编译失败。推荐 string-based type check 替代。

### 推荐 Diagnostic

1. `MMSStreamTerminalView` 加 `addSubview(_:)` override，拦截 CaretView 并打印 call stack
2. `feedPreservingScroll` 加 yDisp vs contentOffset delta log
3. `printf` 对照实验（有/无 `ESC[K`）

### 推荐 Patch

- **Patch B（如果 H1 确认）**：`addSubview` 拦截 CaretView，用 string-based type check 避免跨模块编译问题
- **Patch C（如果 H2 确认）**：`feedPreservingScroll` 中同步 `yDisp` + `contentOffset`

### 详细分析

完整分析见 `.ai/plan/progress/swiftterm-ghost-external-review-qwen.md`。

---

## 2026-05-16 Independent External Review — kimi-k2.6

Agent/Model: kimi-k2.6
Scope: research/docs-only, no code changes
Status: analysis-complete

### 核心声明：旧分析大量引用已不存在的代码

`Docs/swiftterm_ghost_analysis.md` 中 Hypothesis 1 及推荐 Patch 1/1-alt/2/3 引用的 `quarantineSwiftTermCaretViews()`、`flushDisplayAfterOutboundInput()`、`updateMobileCursorOverlay()`、`isSwiftTermCaretView()`、`redrawLastMobileCursorFrame()` 等方法，在当前 `SwiftTerminalCanvasView.swift:524-623` 的 `MMSStreamTerminalView` 中 **已全部移除**。

- `MMSStreamTerminalView` 当前只有：`feedPreservingScroll`、override `setContentOffset` / `layoutSubviews` / `paste` / `keyCommands`、`applyTerminalFontIfNeeded`、`disableSwiftTermAccessory`。
- 无任何 CaretView quarantine、addSubview 拦截、draw override。
- 因此基于 "quarantine race" 的旧 patch 方案在当前代码基上 **无法直接应用**。

### 重新评估根因

**Hypothesis A: SwiftTerm iOS renderer display invalidation + CaretView subview compositing race（概率 ~75%）**

#### 机制

`AppleTerminalView.swift:1454-1503` 中 `updateDisplay()` 的 iOS path 仅用 coarse invalidation：

```swift
#else
// TODO iOS: need to update the code above, but will do that when I get some real
// life data being fed into it.
setNeedsDisplay(bounds)
#endif
```

每次输入 echo 回来：
1. `feed()` → `queuePendingDisplay()` 16ms throttle
2. `updateDisplay()` → **先 `updateCursorPosition()` 移动 `CaretView` subview**
3. 再 `setNeedsDisplay(bounds)`

`CaretView` 是 `layer.isOpaque = false` 的 subview。`drawCursor()` 在 block 模式下填充整个 bounds 并用 `CTFontDrawGlyphs` 绘制字符 glyph。`UIScrollView` 的 tile-based compositor 在 rapid update 时会 coalesce display transaction。CaretView 被移动后，旧 frame 区域的 compositor tile 可能未在同一周期内被 parent `draw(_:)` 完全覆盖，留下 transient glyph blending artifact。

切换 app / full redraw 强制 flush compositor，故 ghost 消失。

#### 与旧分析的校准

| 旧结论 | 评估 |
|--------|------|
| Peirce: dirty-rect / contentOffset 不一致 | **概率低**。iOS path 已用 `contentOffset.y` 计算 visible rows（line 1037-1046），不依赖 `dirtyRect`；且 `setNeedsDisplay(bounds)` 标记全 bounds dirty。 |
| Kierkegaard: Bridge bytes/order | **概率 ~20%**。Bridge 侧有 seq/dedupe，且 ghost 是 visual-only。不能完全排除，但低于 renderer。 |
| 旧 Docs Hypothesis 1: CaretView quarantine race | **前提失效**。当前代码已无 quarantine，ghost 仍存在。说明问题不在 quarantine timing，而在 CaretView 本身的 compositing 行为。 |
| mimo/qwen: CaretView `addSubview` + `setText` 导致 GPU 残留 | **方向一致，但解释需修正**。不是 "quarantine 后被重新加回来"，而是 **每次 `updateDisplay()` 都移动 CaretView + 重绘 glyph**，compositor 在 coarse invalidation 下丢帧。 |

### 最小 Diagnostic Patch

**文件**：`.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift`
**函数**：`updateCursorPosition()`

临时添加 log，验证 old frame 与 dirtyRect 关系：

```swift
func updateCursorPosition() {
    guard let caretView else { return }
    let oldFrame = caretView.frame
    #if os(iOS)
    print("[GhostDiag] oldFrame=\(oldFrame) newRow=\(buffer.y) newCol=\(buffer.x)")
    #endif
    ...
}
```

同时在 `iOSTerminalView.swift` `draw(_:)` 中加：

```swift
override public func draw(_ dirtyRect: CGRect) {
    print("[GhostDiag] dirtyRect=\(dirtyRect) bounds=\(bounds) offset=\(contentOffset)")
    ...
}
```

> 临时 patch，`swift package resolve` 会丢失，仅用于诊断。

### 最小 Real Patch

#### 方案 1（推荐，app-level，不改动 SwiftTerm source）

**核心**：将 cursor style 从 block 改为 bar/underline。

- block cursor 绘制完整字符 glyph（`region = bounds`），ghost 表现为完整双字符/影子，最扎眼。
- bar/underline 只画 2px 区域，即使 compositor 残留也几乎不可见。
- **最小侵入、最低风险、可立即验证**。

**文件**：`CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`
**位置**：`makeUIView` 或 `configure`

```swift
terminalView.getTerminal().options.cursorStyle = .steadyBar
terminalView.updateCaretView()
```

副作用：cursor 变竖线。若用户坚持 block cursor，采用方案 2。

#### 方案 2（根治，需 patch SwiftTerm source）

**核心**：在 `updateCursorPosition()` 移动 CaretView 前，显式 invalidate old frame。

**文件**：`.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift`

```swift
func updateCursorPosition() {
    guard let caretView else { return }
    ...
    // 在设置新 frame 前，强制旧位置立即失效
    #if os(iOS) || os(visionOS)
    setNeedsDisplay(caretView.frame)
    #endif
    caretView.frame.origin = ...
    caretView.setText(ch: ...)
}
```

持久化：fork SwiftTerm 或 vendoring，不要升级到 `602be53`。

### 降级方案（若根治成本过高）

1. 默认 cursor style 改为 bar（方案 1），ghost 从全字符残留降级为 2px 线残留。
2. 保持 `replaysSwiftTermAfterInput = false`。
3. 若用户坚持 block cursor，可在 Settings 提供 cursor style 选项，默认 bar，可选 block。

绝不禁用 SwiftTerm。

### 验证计划

1. **Build generic**：
   ```bash
   xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData-ghost-next CODE_SIGNING_ALLOWED=NO build
   ```

2. **Build device** + bump `1.7.54` build `92`：
   ```bash
   HOME=/Users/xin xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'id=00008150-0008781C36D9401C' -derivedDataPath .build/DerivedData-device build
   ```

3. **Install**：
   ```bash
   xcrun devicectl device install app --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 .build/DerivedData-device/Build/Products/Debug-iphoneos/CodexMobile.app
   ```

4. **Smoke**：连续输入字符、切换 app、滚动到中间输入，观察 ghost 是否消失或降级为不可见。

5. **Bridge regression**：
   ```bash
   HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test --prefix mms-remote-bridge
   ```

### 与之前 agent 对比总结

| Agent | 最高概率根因 | 关键差异 |
|-------|-------------|---------|
| Peirce | dirty-rect / contentOffset | 被代码证伪：iOS 已用 `contentOffset.y` |
| Kierkegaard | Bridge bytes/order | 概率低，ghost 是 visual-only |
| deepseek-v4-flash | CaretView glyph overlay + coordinate mismatch | 正确指出 `CaretView` 是 `internal`，跨模块访问受限 |
| mimo-v2.5-pro | CaretView `addSubview` + `setText` GPU 残留 (85%) | 方向对，但引用的 quarantine 代码已不存在 |
| qwen3.6-plus | CaretView block glyph + yDisp/contentOffset 错位 (75%) | 方向对，保留 yDisp 错位作为次要假设 |
| **kimi-k2.6** | **CaretView compositing race + coarse invalidation (75%)** | **强调旧代码前提失效；提出 bar cursor workaround 作为最小侵入方案** |

### 详细分析

完整分析见 `.ai/plan/progress/swiftterm-ghost-external-review.md`。
