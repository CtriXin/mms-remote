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
