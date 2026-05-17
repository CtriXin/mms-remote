# SwiftTerm Ghost External Review — glm-5.1

- Timestamp: 2026-05-17T03:30:00-04:00
- Agent/Model: glm-5.1 (independent external review)
- Scope: SwiftTerm iOS visual ghost/影子 root cause analysis, research/docs-only
- Status: completed

---

## 1. 最高概率根因

**SwiftTerm iOS `draw()` 用 `dirtyRect` 做背景清除，而非 `bounds`；与 CaretView block-cursor glyph 渲染叠加后产生视觉残留。概率 ~70%。**

### 证据链

**核心代码路径** (`IOSTerminalView.swift:1288-1304`):

```swift
override public func draw (_ dirtyRect: CGRect) {
    guard let context = getCurrentGraphicsContext() else { return }
    nativeBackgroundColor.set()
    context.fill([dirtyRect])  // ← 只清除 dirtyRect，不是 bounds
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: 0, y: -frame.height)
    drawTerminalContents(dirtyRect: dirtyRect, context: context, bufferOffset: 0)
}
```

**关键发现**：当前 `MMSStreamTerminalView`（`SwiftTerminalCanvasView.swift:524-623`）**没有任何 CaretView quarantine 逻辑**。现有分析文档 `Docs/swiftterm_ghost_analysis.md` 中的 quarantine/addSubview override / `flushDisplayAfterOutboundInput` 等 patch 已经被清除。当前代码是干净的 SwiftTerm 子类，只有 scroll preservation。

这意味着：
- 之前的 CaretView quarantine 方案已经被移除
- Ghost 仍然存在，说明根因不在 quarantine 逻辑
- 需要从 SwiftTerm 自身的渲染机制找根因

### 根因机制

1. `CaretView` 是独立 `UIView`，在 block cursor 样式下渲染 **完整字符 glyph**（`CaretView.swift:31-65`，`drawCursor` method）
2. `drawCursor` 先填充整个 bounds 为 cursor color，再在上方绘制字符 glyph
3. 当 cursor 从位置 A 移到位置 B：
   - `updateCursorPosition()` 改变 `caretView.frame.origin`
   - UIKit 应标记 old frame 和 new frame 为 dirty
   - `TerminalView.draw(dirtyRect)` 被调用时，**`dirtyRect` 可能不覆盖 old frame 全部区域**
   - `context.fill([dirtyRect])` 只清除 dirty rect 范围
   - old frame 区域可能残留 CaretView 之前 commit 的 glyph 像素

4. `updateDisplay(notifyAccessibility:)` (`AppleTerminalView.swift:1454-1490`) 对 iOS 做的是 `setNeedsDisplay(bounds)`，但 UIKit **可能将实际 delivered `dirtyRect` 缩小**（dirty rect coalescing 优化）

5. 如果 `terminal.getUpdateRange()` 返回 nil（没有行变化），`setNeedsDisplay` **根本不会被调用**——但 `updateCursorPosition()` 已经执行了。这意味着 CaretView 移动后，TerminalView 可能**不会重绘** old frame 区域。

### 次要辅助因素

`updateDisplay()` 的 early return 路径 (`AppleTerminalView.swift:1458-1465`):

```swift
guard let (rowStart, rowEnd) = terminal.getUpdateRange() else {
    // 没有 dirty rows → 直接 return
    // 但 updateCursorPosition() 已经修改了 CaretView frame！
    return
}
```

当只有 cursor 移动没有行内容变化时（比如输入空格后光标右移），TerminalView **不会触发 `setNeedsDisplay`**。CaretView 的 old frame 区域完全依赖 UIKit 的自动 invalidation，而 UIKit 的 dirty rect coalescing 可能不够精确。

---

## 2. 根因分类

**SwiftTerm renderer/compositor + iOS host integration 的混合问题。**

- SwiftTerm renderer：`draw()` 用 `dirtyRect` 而非 `bounds` 做背景清除
- CaretView：block cursor 样式渲染字符 glyph，提供了 "ghost 源材料"
- iOS host integration：`MMSStreamTerminalView.feedPreservingScroll()` 的 contentOffset 修改可能干扰 UIKit dirty rect 计算
- **不是 Bridge bytes/order 问题**：CR/LF normalization 已修复 garble，ghost 是纯视觉残留

---

## 3. 禁止继续尝试的方案

| 方案 | 禁止原因 |
|------|----------|
| 禁用 SwiftTerm | 用户明确反对 |
| replay/full-screen refresh 当最终方案 | 用户不接受闪屏 |
| `1.7.49/87` RunLoop/default-mode drain | 破坏 echo/order，反馈更差 |
| CaretView quarantine / addSubview override | 当前代码已清除这些逻辑，ghost 仍在；说明 quarantine 方向错误 |
| `replay: false` 启动 stream | 导致空白启动 |
| 直接升级 SwiftTerm latest | Metal Toolchain 缺失，generic build 失败 |
| hidden input proxy + mobile cursor overlay | 已尝试，ghost 仍在 |

---

## 4. 最小 Diagnostic Patch

### 4a. 验证 dirtyRect 覆盖范围

**文件**: `SwiftTerminalCanvasView.swift`，`MMSStreamTerminalView` class

```swift
override public func draw(_ dirtyRect: CGRect) {
    print("[GHOST-GLM51] draw dirtyRect=\(dirtyRect) bounds=\(bounds) offset=\(contentOffset)")
    super.draw(dirtyRect)
}
```

**观察**：如果 `dirtyRect` 小于 `bounds`，确认 dirty rect coalescing 在截断清除范围。

### 4b. 验证 updateDisplay 的 early return 路径

**文件**: `SwiftTerminalCanvasView.swift`，`MMSStreamTerminalView` class

```swift
// 需要 override updateDisplay 或 swizzle
// 替代方案：在 addSubview 中检测 CaretView
override func addSubview(_ view: UIView) {
    let isCaret = view is CaretView || String(describing: type(of: view)).contains("Caret")
    if isCaret {
        print("[GHOST-GLM51] CaretView addSubview frame=\(view.frame) offset=\(contentOffset)")
    }
    super.addSubview(view)
}
```

### 4c. 记录字段

每次 draw 调用记录：`dirtyRect`, `bounds`, `contentOffset`, `hasCaretSubview`

---

## 5. 最小 Real Patch

### 推荐方案：Override `draw()` 确保 full-bounds 背景清除

**文件**: `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`
**位置**: `MMSStreamTerminalView` class（line 524 附近）

```swift
override public func draw(_ dirtyRect: CGRect) {
    guard let context = UIGraphicsGetCurrentContext() else { return }
    // Full-bounds background clear instead of dirtyRect-only
    nativeBackgroundColor.set()
    context.fill([bounds])
    context.scaleBy(x: 1, y: -1)
    context.translateBy(x: 0, y: -frame.height)
    drawTerminalContents(dirtyRect: bounds, context: context, bufferOffset: 0)
}
```

**核心思路**：用 `bounds` 替代 `dirtyRect` 做背景清除和内容重绘，确保整个可见区域每帧都被完整重绘。这消除了 dirty rect coalescing 可能遗漏的区域。

**代价**：每帧全屏重绘而非增量重绘。但当前 iOS 路径已经是 `setNeedsDisplay(bounds)` + 全行遍历，所以实际开销增加有限。

### 备选方案：CaretView 改为 bar/underline 样式

如果 full-bounds 重绘性能不可接受，可以将 CaretView 改为 bar 或 underline 样式（不渲染字符 glyph）：

**文件**: `SwiftTerminalCanvasView.swift`，`makeUIView` 中

```swift
// 在 configure 或 makeUIView 中
terminalView.getTerminal().options.cursorStyle = .steadyBar
```

Bar cursor 不渲染字符 glyph（`CaretView.swift:33-34`，只填充 2px 宽条），从根本上消除 glyph 残留源。

---

## 6. 验证计划

不跑 Xcode tests。手动验证：

### Smoke Test

1. Build + install 到 `song的iPhone`
2. 打开 Terminal tab，选 SwiftTerm renderer
3. 快速输入 `abcdef`，观察是否出现 ghost
4. 输入 `ls -la` + Enter，观察 output 中是否有 ghost
5. Scroll 到中间位置，输入字符，观察
6. 切换到其他 tab 再回来，确认 ghost 清除

### Build 命令

```bash
# Generic iOS build (no signing)
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

xcrun devicectl device install app \
  --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 \
  .build/DerivedData-device/Build/Products/Debug-iphoneos/CodexMobile.app
```

### 对照实验

先加 diagnostic patch（4a），确认 `dirtyRect < bounds`，再加 real patch 确认 ghost 消失。

---

## 7. 降级方案

如果 full-bounds `draw()` 仍不能解决，或性能不可接受：

1. **CaretView 改 bar/underline 样式**（不渲染 glyph）— 消除 ghost 源材料
2. **周期性 `setNeedsDisplay(bounds)` 无效化**：每次 feed 后 50ms 强制 `setNeedsDisplay(bounds)` + `layer.displayIfNeeded()`
3. **降低 cursor 样式为 underline**（最小视觉代价，最大 ghost 消除）

以上均不需要禁用 SwiftTerm。

---

## 与之前 Agent 结论的对比

| 维度 | Peirce | Kierkegaard | glm-5.1（本分析） |
|------|--------|-------------|------------------|
| 主根因 | dirty-rect vs contentOffset 坐标不一致 | Bridge replay/live/input order | `draw()` 背景清除用 `dirtyRect` 非 `bounds` + early return 路径不触发重绘 |
| CaretView 角色 | 放大影子感，但 quarantine 不是根修 | 未重点关注 | block cursor 渲染 glyph 是 ghost 的 "源材料"，但直接原因是背景清除不完整 |
| Patch 方向 | SwiftTerm source-level draw visibleRect/row clear | Bridge stream trace + per-pane input queue | Override `draw()` 做 full-bounds 清除，或改 bar cursor |
| 关键差异 | — | — | 发现当前代码已无 quarantine 逻辑，ghost 仍在；`updateDisplay` 的 `getUpdateRange()` nil path 不调用 `setNeedsDisplay` |

**重要更正**：`Docs/swiftterm_ghost_analysis.md` 中的 Hypothesis 1（CaretView quarantine race）基于已不存在的代码逻辑。当前 `MMSStreamTerminalView` 没有 quarantine、没有 `flushDisplayAfterOutboundInput`、没有 addSubview override。Ghost 在没有这些代码的情况下仍然复现，证明根因不在 quarantine race。
