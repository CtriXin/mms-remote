## 2026-05-17T03:30:00-04:00 External Review — glm-5.1 (独立验证)

### 关键更正

**当前 `MMSStreamTerminalView`（SwiftTerminalCanvasView.swift:524-623）已移除所有 CaretView quarantine 逻辑。** 包括：
- `quarantineSwiftTermCaretViews()`
- `flushDisplayAfterOutboundInput()`
- `schedulePostStreamCursorRefresh()`
- `addSubview` override（CaretView 拦截）
- `updateMobileCursorOverlay()` / `redrawLastMobileCursorFrame()`

之前的 Hypothesis 1（CaretView quarantine race，概率 ~70%）基于已不存在的代码。Ghost 在没有 quarantine 的干净 SwiftTerm 子类中仍然复现，排除 quarantine race 作为根因。

### 修正后根因排序

**Hypothesis 1（修正）：SwiftTerm iOS `draw()` 用 `dirtyRect` 做背景清除 + `updateDisplay` early return 不触发重绘（概率 ~70%）**

**机制**：

1. `IOSTerminalView.swift:1296-1297`:
   ```swift
   nativeBackgroundColor.set()
   context.fill([dirtyRect])  // 只清除 dirtyRect，不是 bounds
   ```

2. `AppleTerminalView.swift:1454-1465`:
   ```swift
   func updateDisplay(notifyAccessibility: Bool) {
       updateCursorPosition()  // CaretView frame 改变 + setText()
       guard let (rowStart, rowEnd) = terminal.getUpdateRange() else {
           return  // 没有 dirty rows → 不调用 setNeedsDisplay！
       }
       // ...
       setNeedsDisplay(bounds)
   }
   ```

3. 当只有 cursor 移动没有行内容变化时，`getUpdateRange()` 返回 nil → `setNeedsDisplay` 不被调用 → CaretView old frame 区域**不会被 TerminalView 重绘清除**

4. 即使 `setNeedsDisplay(bounds)` 被调用，UIKit dirty rect coalescing 可能将实际 delivered `dirtyRect` 缩小

5. CaretView block cursor 样式渲染字符 glyph（`CaretView.swift:46-65`），提供了 ghost 的视觉 "源材料"

**证据**：

| 证据 | 说明 |
|------|------|
| ✅ 输入后出现 | cursor 移动触发 `updateCursorPosition`，但如果行内容不变则 `getUpdateRange` 返回 nil |
| ✅ 切换/刷新后消失 | 切换触发 view rebuild 或 full invalidate |
| ✅ ghost 是字符形状 | 来自 CaretView 的 `setText()` → CTLine glyph 渲染 |
| ✅ 无 quarantine 代码时仍复现 | 当前代码没有 quarantine，ghost 仍在 |
| ✅ SwiftTerm 源码有 TODO | `// TODO iOS: need to update the code above` — 作者自知 iOS 路径不完善 |

**Hypothesis 2：CaretView block cursor glyph + CoreAnimation layer commit 时序（概率 ~20%）**

辅助因素。即使 dirty rect 正确，CoreAnimation 的 layer commit 和 display cycle 时序可能导致 CaretView glyph 在 old position 已经 commit 到 backing store 后才被标记为 dirty。这与 H1 叠加。

**Hypothesis 3：Bridge byte order / replay 尾部重复（概率 ~10%）**

Kierkegaard 指出的风险仍然存在但概率低。CR/LF normalization 已修复 garble，ghost 是纯视觉现象而非 buffer 内容错误。

### 推荐 Real Patch

**方案 A（推荐）：Override `draw()` 做 full-bounds 背景清除**

文件：`CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`，`MMSStreamTerminalView` class

```swift
override public func draw(_ dirtyRect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    nativeBackgroundColor.set()
    context.fill([bounds])  // full-bounds clear
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: 0, y: -frame.height)
    drawTerminalContents(dirtyRect: bounds, context: context, bufferOffset: 0)
}
```

**方案 B（降级）：Cursor 改 bar/underline 样式**

不渲染 glyph，从源头消除 ghost 材料：

```swift
// 在 makeUIView 或 configure 中
terminalView.getTerminal().options.cursorStyle = .steadyBar
```

### 不需要改的

- Bridge 侧不需要修改（`terminal-stream-hub.js`, `tmux-control-adapter.js` 已正确）
- `CodexService+Terminal.swift` 不需要修改
- `replaysSwiftTermAfterInput` 已正确设为 `false`
- 不需要恢复 quarantine 逻辑
- 不需要 hidden input proxy

### 验证命令

```bash
# Diagnostic: 先加 draw override 带 log
# Real patch: full-bounds draw override

# Generic build
xcodebuild -project CodexMobile/CodexMobile.xcodeproj \
  -scheme CodexMobile -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .build/DerivedData-ghost-glm51 \
  CODE_SIGNING_ALLOWED=NO build

# Device build + install
xcodebuild -project CodexMobile/CodexMobile.xcodeproj \
  -scheme CodexMobile -configuration Debug \
  -destination 'id=00008150-0008781C36D9401C' \
  -derivedDataPath .build/DerivedData-device build
```

### Bridge tests (unchanged)

```bash
HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test --prefix mms-remote-bridge
```

---

## 8. 社区验证与替代方案调研（2026-05-17）

### 8.1 SwiftTerm 社区已知问题

| Issue | 描述 | 与本项目 ghost 的关系 |
|-------|------|----------------------|
| [#231 Terminal Rendering Defect](https://github.com/migueldeicaza/SwiftTerm/issues/231) | CodeEdit 团队报告 SwiftTerm rendering defect，涉及终端渲染异常 | 直接相关 — 其他 SwiftTerm 用户遇到同类渲染问题 |
| [#137 Multi-threading Terminal](https://github.com/migueldeicaza/SwiftTerm/issues/137) | SwiftTerm 多线程 lock 机制讨论 | 间接相关 — `terminalLock`/`terminalUnlock` 影响 feed 与 draw 的线程安全 |
| [#342 setCursorColor() not working](https://github.com/migueldeicaza/SwiftTerm/issues/342) | cursor 颜色设置不生效，涉及 CaretView 渲染路径 | 佐证 CaretView 渲染路径有已知缺陷 |
| [#227 Cursor positioning with CJK/emoji](https://github.com/migueldeicaza/SwiftTerm/issues/227) | CJK/emoji 字符宽度导致 cursor 定位偏移 | 佐证 cursor 定位逻辑在 iOS 上不完善 |

### 8.2 UIKit dirty rect 行为验证

社区确认的关键行为：

1. **`setNeedsDisplayInRect:` 不保证 partial redraw**（[SO: CALayer setNeedsDisplayInRect](https://stackoverflow.com/questions/9809306/calayer-setneedsdisplayinrect-causes-the-whole-layer-to-be-redrawn)）— UIKit 可能将多个 dirty rect 合并为 bounding rect，或直接 full redraw
2. **UIKit backing layer 特殊行为** — `UIView` 的 backing layer 可能在 `setNeedsDisplayInRect:` 时内部标记 entire layer needs display
3. **`clearsContextBeforeDrawing` 默认 `true`** — 但只清除 `draw()` 实际收到的 `dirtyRect` 区域，不是 `bounds`

**结论**：UIKit dirty rect coalescing 行为不可预测，依赖 `dirtyRect` 做精确背景清除不可靠。这进一步支持 full-bounds 清除方案。

### 8.3 其他 iOS 终端模拟器做法

| 项目 | Cursor 渲染策略 | Ghost 处理 |
|------|----------------|-----------|
| **LibTerm** / **La Terminal**（SwiftTermApp） | 直接用 SwiftTerm 引擎，同 Miguel de Icaza | 未公开讨论 ghost 问题 |
| **Blink Shell** | 开源（[blinksh/blink](https://github.com/blinksh/blink)），用自定义 Metal 渲染 + 独立 cursor overlay layer | cursor 作为独立 CALayer 叠加，不参与主 draw cycle，从架构上避免 dirty rect 问题 |
| **iSH** | 用 UIView `draw()` 但 cursor 为独立 subview | 类似方案 — cursor 移动只更新自身 layer，不依赖主 view redraw |

**关键发现**：Blink Shell 和 iSH 的做法是将 cursor **从主渲染路径分离**，使用独立 layer/overlay。这从根本上避免 dirty rect coordination 问题。

### 8.4 替代方案评估

| 方案 | 优点 | 缺点 | 推荐度 |
|------|------|------|--------|
| **A. Override `draw()` full-bounds 清除** | 最小改动，不改 SwiftTerm 源码 | 每帧全屏重绘，但增量开销有限（已遍历所有行） | ★★★★★ 首选 |
| **B. Cursor 改 bar/underline** | 从源头消除 glyph ghost 材料 | 改变用户体验，block cursor 是常见期望 | ★★★ 降级 |
| **C. 独立 cursor overlay layer（Blink 方案）** | 架构最优，彻底分离 | 需要 fork/patch SwiftTerm CaretView 逻辑，改动大 | ★★ 长期 |
| **D. 每次 cursor 移动 invalidate old+new frame union** | 精确 dirty rect | 需 hook `updateCursorPosition()`，SwiftTerm 源码改动 | ★★★ 精确但侵入 |
| **E. `setNeedsDisplay(bounds)` on every `queuePendingDisplay`** | 不改 draw 逻辑 | 需 override `queuePendingDisplay`，仍有 16ms throttle 窗口 | ★★ |

### 8.5 最优方案确认

**方案 A（full-bounds draw override）仍然是最优选择**，理由：

1. **最小改动**：只 override 一个方法，不改 SwiftTerm 源码
2. **社区验证**：dirty rect coalescing 不可靠是 UIKit 已知行为，full-bounds 清除是标准 workaround
3. **性能可控**：SwiftTerm iOS 已用 `setNeedsDisplay(bounds)` + 全行遍历，full-bounds 清除不增加额外行扫描
4. **降级路径清晰**：如果 A 不够，可退到 B（bar cursor）或 D（精确 invalidate）

如果方案 A 在设备上验证通过，无需尝试更复杂的方案。如果仍有残留，叠加方案 B（bar cursor）基本可以根治。
