# SwiftTerm Ghost 外部 Agent 独立 Review

- **Timestamp**: 2026-05-16
- **Agent**: kimi-k2.6
- **Scope**: iOS SwiftTerm visual ghost/shadow 根因独立验证
- **Status**: review-completed; docs written
- **Device Point**: iOS `1.7.53 build 91` on `song的iPhone`

---

## 独立审阅声明

本 review 基于 **当前实际代码** 独立完成，不盲信先前 agent 结论。特别注意：先前分析引用的 `quarantineSwiftTermCaretViews()`、`flushDisplayAfterOutboundInput()`、`mobileCursorOverlay` 等代码在当前 `SwiftTerminalCanvasView.swift` 中 **已不存在**（native SwiftTerm input/caret path 已恢复）。因此旧结论需要重新校准。

---

## 当前现象（与用户确认一致）

1. 输入后出现视觉 ghost/影子/双字符残留。
2. 切换 app 再回来 → 消失。
3. replay / full redraw 能清掉，但会闪一下。
4. **buffer 内容正确**，不是真实重复字符。
5. 空白启动、`cd` 显示异常、乱码均已解决，只剩 ghost。

---

## 根因排序（独立判断）

### Hypothesis A: SwiftTerm iOS renderer display invalidation + CaretView subview compositing race（概率 ~75%）

#### 机制

`AppleTerminalView.swift:1454-1503` 中 `updateDisplay()` 的 iOS path：

```swift
#else
// TODO iOS: need to update the code above, but will do that when I get some real
// life data being fed into it.
setNeedsDisplay(bounds)
#endif
```

- iOS 端未做精确 dirty rect，而是粗暴 `setNeedsDisplay(bounds)`。
- 每次输入 echo 回来 → `feed()` → `queuePendingDisplay()` 16ms throttle → `updateDisplay()` → **先调用 `updateCursorPosition()` 移动 `CaretView` subview**，再 `setNeedsDisplay(bounds)`。
- `CaretView` 是 `layer.isOpaque = false` 的 subview，使用 Core Graphics 直接绘制 block cursor + glyph（`CaretView.swift:drawCursor`）。
- `UIScrollView` 的 tile-based compositor 在 rapid update 时会 coalesce display transaction。CaretView 被移动后，旧 frame 区域的 compositor tile 可能未在同一 v-sync 周期内被 parent 的 `draw(_:)` 完全覆盖，留下 transient glyph blending artifact。
- 切换 app / full redraw 强制 flush compositor，所以 ghost 消失。

#### 证据

| 证据 | 说明 |
|------|------|
| 输入后出现 | 正是 `feed()` → `updateDisplay()` → CaretView move 的高频路径 |
| 切换后消失 | Core Animation full flush / view hierarchy rebuild 清除 stale tile |
| full redraw 能清 | 强制完整重绘，覆盖 compositor cache |
| buffer 内容正确 | 不是 bytes 重复，是 visual-only artifact |
| 旧 quarantine 代码已不存在 | 排除了旧分析中 "quarantine race" 的主因地位 |

#### 反证与回应

| 反证 | 回应 |
|------|------|
| "`draw(_:)` 里已经 `context.fill([dirtyRect])` 清了背景" | 清的是 parent CGContext，但 CaretView 是独立 subview layer；UIKit compositor 的 tile cache 不一定同步失效 |
| "`setNeedsDisplay(bounds)` 应该覆盖整个可见区域" | `UIScrollView` 对 `setNeedsDisplay(bounds)` 的调度会 coalesce；old caret frame 的 clear 可能与 CaretView move 不在同一 transaction |

### Hypothesis B: Bridge replay/live/input order 或重复 bytes（概率 ~20%）

#### 机制

- `terminal-stream-hub.js` 的 replay buffering + `dropReplayMirroredPrefix` 使用文本 heuristic，可能漏掉 ANSI tail 重复。
- `tmux-control-adapter.js` 的 `normalizeTerminalOutputText` 做 CRLF 补全和 duplicate CR collapse，但 cross-chunk state（`lastWasCR`）在 `reset()` 时才会重置。
- iOS input 通过 `Task { try await codex.sendTerminalData(...) }` 发出，无 per-pane queue；但 Bridge 侧 tmux 是单进程，顺序由内核 pipe 保证。

#### 评估

- 已有 seq 排序 + dedupe（`shouldSuppressDuplicateSend`）。
- 用户确认 buffer 内容正确，ghost 是 visual-only。
- 若为 bytes 重复，切换 app 不应消除（buffer 里的重复还在）。
- **本 hypothesis 未被完全排除，但优先级低于 renderer。**

### Hypothesis C: `feedPreservingScroll` / `setContentOffset` override 干扰 dirty rect（概率 ~5%）

- `MMSStreamTerminalView` override `setContentOffset` 并在 `feedPreservingScroll` 中恢复 scroll offset。
- 但 `feedPreservingScroll` 仅在 `!isNearBottom()` 时生效，且直接调用 `super.setContentOffset`，绕过了 override 的 y-preserving 逻辑。
- 当用户在底部输入时（最常见场景），`feedPreservingScroll` 不做任何 scroll 恢复，因此几乎不影响。
- 概率极低。

---

## 已失败方案（必须禁止）

| 方案 | 状态 | 原因 |
|------|------|------|
| 禁用 SwiftTerm | 禁止 | 用户明确反对 |
| replay/full-screen refresh 当最终修复 | 禁止 | 闪屏，用户不接受 |
| `1.7.49/87` RunLoop/default-mode drain | 禁止 | 已破坏 echo/order，用户反馈更差 |
| hidden input proxy + cursor quarantine | **已移除** | 当前代码已恢复 native caret path；旧分析基于此假设已失效 |
| startup stream 纯 `replay: false` | 禁止 | 曾导致空白启动 |
| 无条件升级 SwiftTerm latest `602be53` | 禁止 | Metal Toolchain 缺失，generic build 失败 |

---

## 最小 Diagnostic Patch

**目标**：验证 old caret frame 是否在移动前被正确 invalidate。

**文件**：`.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift`

**位置**：`updateCursorPosition()` 函数（约 line 1505）

**临时修改**：

```swift
func updateCursorPosition()
{
    guard let caretView else { return }
    let oldFrame = caretView.frame
    // --- diagnostic start ---
    #if os(iOS)
    print("[GhostDiag] updateCursorPosition old=\(oldFrame) newRow=\(buffer.y) newCol=\(buffer.x)")
    #endif
    // --- diagnostic end ---
    ... // 原有逻辑
}
```

同时在 `iOSTerminalView.swift` `draw(_:)` 中加：

```swift
override public func draw (_ dirtyRect: CGRect) {
    print("[GhostDiag] draw dirtyRect=\(dirtyRect) bounds=\(bounds) offset=\(contentOffset)")
    ...
}
```

**验证方式**：Simulator 或 device 上输入几个字符，观察 console：
- 若 `dirtyRect` 始终等于 `bounds`，说明 coarse invalidation 生效。
- 若 old caret frame 与 dirtyRect 有交集但仍出现 ghost，说明是 compositor timing 问题而非 coverage 问题。

> ⚠️ 这是 **本地 checkout 临时 patch**，`swift package resolve` 会丢失；仅用于诊断。

---

## 最小 Real Patch

### 方案 1（推荐，不改动 SwiftTerm source，app-level）

**核心思路**：将 cursor style 从 block 改为 bar/underline。

- block cursor 会绘制完整字符 glyph（`region = bounds`），ghost 表现为一整个双字符/影子，最扎眼。
- bar/underline 只绘制 2px 区域（`width: 2` 或 `height: 2`），即使 compositor 留下残留，肉眼几乎不可见。
- 这是 **最小侵入、最低风险、可立即验证** 的 workaround。

**文件**：`CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`

**位置**：`makeUIView` 或 `configure`

**代码**：

```swift
func makeUIView(context: Context) -> TerminalView {
    let terminalView = MMSStreamTerminalView(...)
    ...
    terminalView.getTerminal().options.cursorStyle = .steadyBar
    terminalView.updateCaretView()
    return terminalView
}
```

或在 `configure` 中：

```swift
private func configure(_ terminalView: TerminalView) {
    ...
    terminalView.getTerminal().options.cursorStyle = .steadyBar
    terminalView.updateCaretView()
}
```

**副作用**：cursor 变成竖线，用户可能需要适应。若用户坚持 block cursor，则采用方案 2。

### 方案 2（根治，需 patch SwiftTerm source）

**核心思路**：在 `updateCursorPosition()` 移动 CaretView 前，显式 invalidate old frame。

**文件**：`.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift`

**函数**：`updateCursorPosition()`

**修改**：

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

    // --- patch start ---
    #if os(iOS) || os(visionOS)
    let oldFrame = caretView.frame
    setNeedsDisplay(oldFrame)  // 强制旧位置立即失效
    #endif
    // --- patch end ---

    let doublePosition = buffer.lines [vy].renderMode == .single ? 1.0 : 2.0
    #if os(iOS) || os(visionOS)
    let offset = (cellDimension.height * (CGFloat(buffer.y+(buffer.yBase))))
    let lineOrigin = CGPoint(x: 0, y: offset)
    #else
    let offset = (cellDimension.height * (CGFloat(buffer.y-(buffer.yDisp-buffer.yBase)+1)))
    let lineOrigin = CGPoint(x: 0, y: frame.height - offset)
    #endif
    caretView.frame.origin = CGPoint(x: lineOrigin.x + (cellDimension.width * doublePosition * CGFloat(buffer.x)), y: lineOrigin.y)
    caretView.setText (ch: buffer.lines [vy][buffer.x])
}
```

**持久化方式**：由于 SwiftTerm 是 SPM checkout，source patch 会在 `swift package resolve` 后丢失。建议：
1. Fork SwiftTerm 到本地/组织仓库；
2. 应用 patch 并 pin 到该 fork；
3. 或 vendor SwiftTerm 源码进项目。

> 注意：不要升级到 `602be53`，先基于当前可用 revision `9ad1b190` 做最小 patch。

---

## 降级方案（若上述 patch 仍无效）

如果根治成本过高，可接受降级：

1. **默认 cursor style 改为 bar**（如方案 1），ghost 从全字符残留降级为 2px 线残留，体验大幅改善。
2. **保持 `replaysSwiftTermAfterInput = false`**，避免闪屏。
3. **若用户强烈要求 block cursor**，可在设置中提供 cursor style 选项，默认 bar，可选 block（带风险提示）。

绝不禁用 SwiftTerm。

---

## 验证计划

### Smoke Test（不跑 Xcode tests）

1. **Build generic**（验证编译通过）：
   ```bash
   cd /Users/xin/auto-skills/CtriXin-repo/mms-remote
   xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData-ghost-next CODE_SIGNING_ALLOWED=NO build
   ```

2. **Build device**（用于安装）：
   ```bash
   HOME=/Users/xin xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'id=00008150-0008781C36D9401C' -derivedDataPath .build/DerivedData-device build
   ```

3. **Bump version/build**：patch-level fix → `1.7.54` build `92`。

4. **Install**：
   ```bash
   xcrun devicectl device install app --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 .build/DerivedData-device/Build/Products/Debug-iphoneos/CodexMobile.app
   ```

5. **Manual smoke**：
   - 打开 Terminal Swift tab
   - 连续输入字符（如 `ls` 回车、`pwd`、长按重复字符）
   - 观察是否仍有明显 ghost/双字符
   - 切换 app 再回来，确认行为
   - 滚动到中间再输入，确认行为

### Bridge tests（无需 device）

```bash
HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test --prefix mms-remote-bridge
```
确保 terminal-stream-hub / tmux-control-adapter 逻辑无回归。

---

## 风险

| 风险 | 缓解 |
|------|------|
| Patch SwiftTerm source 后 SPM resolve 丢失 | Fork 并 pin，或 vendoring |
| Bar cursor 用户不习惯 | 提供 settings 选项，默认 bar |
| 改 cursor style 后 ghost 仍存在（概率低） | 说明根因更深层，需回到方案 2 + compositor diagnostic |
| 旧分析文档中的 line number 与当前代码不匹配 | 本 review 已重新标注基于当前代码的准确位置 |
