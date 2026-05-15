# 移动端终端模拟器调研报告

> 日期: 2026-05-15 | 作者: Claude (mms-remote agent)
> 目标: 调研开源移动端终端 App 技术栈，为 mms-remote 终端模块提供复用方案

---

## Reviewer 修正

这份文档可以作为未来 Terminal 方向的 research，但不能直接当执行 plan 使用。尤其不要仅因为 `SwiftTerm` 已集成就直接移除 `false &&` 或把 SwiftTerm tab 设为默认入口；只有在 stream lifecycle、replay buffer、输入法/空格/回车、光标、resize、断线恢复、横向溢出、真机验收全部通过后，SwiftTerm 才能成为默认 renderer。

产品定位也要收束：Terminal 是独立入口，不是 Chat 里的小 feature。正式版应保持 `Chats / Terminal` 两个主入口；SwiftTerm 只是 Terminal 的 renderer 实现，不应作为第三个面向用户的长期 tab。

---

## 一、开源终端 App 技术全景

### 1.1 Android 端

| App | Stars | PTY 方案 | 渲染 | 快捷键 | License |
|-----|-------|---------|------|--------|---------|
| **Termux** | 54.9k | JNI → `openpty()`/`forkpty()` via `/dev/ptmx` | 原生 Canvas/Paint 逐字符绘制 | Extra Keys Row (sticky modifier) | GPL-3.0 |
| **ConnectBot** | — | libvterm via JNI (`termlib` 独立库) | Jetpack Compose | 3-state modifier (OFF→TRANSIENT→LOCKED) | Apache-2.0 |
| **jackpal Android Terminal** | — | JNI: `fork()` + `openpty()` + `TIOCSCTTY` | 原生 Canvas | 标准 Android KeyEvent | — |

**Termux 架构要点：**
- 三模块分离: `terminal-emulator/` (纯 Java 模拟器) + `terminal-view/` (Android View) + `app/`
- PTY 分配: `JNI.createSubprocess()` 打开 `/dev/ptmx`，fork 子进程，slave 端做 stdin/stdout/stderr
- 渲染: `TerminalRenderer.java` 用 `android.graphics.Paint` + `Canvas` 逐字符绘制，预计算 ASCII 宽度数组
- 模拟器: `TerminalEmulator.java` 完整 xterm/vt100 状态机，23+ 转义状态，支持鼠标跟踪、OSC 52
- 快捷键: `KeyHandler.java` 映射 Android keycode → 转义序列，支持 Ctrl/Alt/Shift sticky

**ConnectBot 架构要点：**
- 库化设计: `termlib` (终端模拟) + `sshlib` (SSH) + `app` (UI)
- `termlib` 底层是 C 库 libvterm，JNI 暴露为 Kotlin API
- `TerminalKeyListener` 支持 transient (单次) / locked (持续) 两种修饰键模式
- Compose UI + `TerminalKeyboard.kt` 自带方向键和修饰键

### 1.2 iOS 端

| App | PTY 方案 | 渲染 | 快捷键 | License |
|-----|---------|------|--------|---------|
| **Blink Shell** | ios_system + SSH/Mosh (无本地 PTY) | **hterm** (WKWebView) | SmarterKeys (注入 SystemInputAssistantView) | GPL-3.0 |
| **iSH** | 自建 Linux PTY 驱动 (x86 模拟层, C) | **hterm** (WKWebView) | UIKeyCommand + UITextInput | GPL-3.0 |
| **a-Shell** | ios_system 线程流 (无 PTY) | hterm (WKWebView) | UIKeyCommand + 键盘扩展 | BSD-3 |
| **SwiftTerm** | `forkpty()` (仅 macOS, iOS 被 `#if !os(iOS)` 隔离) | CoreGraphics + Metal GPU | Accessory Bar + Custom KeyboardView | MIT |
| **Carnets** | CPython via ZMQ | WKWebView (Jupyter) | WKWebView JS input | BSD-3 |

**Blink SmarterKeys 架构 (iOS 最复杂键盘实现)：**
- 不用 UIInputViewController，用 `KBProxy.swift` 遍历 `SystemInputAssistantView.superview` 层级注入 `KBView`
- 设备适配: iPhone/iPad 9.7/10.5/11/12.9 各有独立布局 + 多语言 (英/俄/法/德/西)
- `KBKeyValue.swift` 定义所有键值: modifier (.cmd/.alt/.ctrl)、导航、F1-F12、文本
- `KBTracker.swift` 检测硬件键盘: iPad `height > 116` = 外接键盘，iPhone `screenHeight >= kbFrameEnd.maxY`

**iSH PTY 实现 (iOS 上最接近真 PTY)：**
- `fs/pty.c`: Linux 模拟内核中的完整 PTY 子系统，master/slave 双向路由
- `app/LinuxPTY.c`: iOS↔模拟内核桥接，`kernel_read()` 读 master → `Terminal_sendOutput_length()` 推 UI
- 分配上限 4096 对 PTY

**SwiftTerm iOS 键盘三层架构：**
1. `iOSAccessoryView` — 键盘上方工具栏: Esc/Ctrl(切换)/Tab + F1-F10 + 箭头(自动重复 600ms→100ms)
2. `iOSKeyboardView` — 10x3 网格全键盘: F1-F10、括号、导航键
3. `iOSDoubleButton` — 双用途按钮: tap=主值，pan+release=副值 (如 Ctrl/Ctrl+Shift)

### 1.3 跨平台

| App | PTY | 渲染 | License |
|-----|-----|------|---------|
| **Jexer** | 无 (TUI 框架，非终端) | 插件后端: Swing / ECMA-48 / Headless | MIT |

Jexer 的价值在 `TKeypress` 抽象: 平台无关的键事件模型，后端做平台特定转换。

---

## 二、技术细节深挖

### 2.1 PTY 分配模式

| 模式 | 代表 | 核心 API | 适用场景 |
|-----|------|---------|---------|
| POSIX PTY via JNI | Termux, ConnectBot | `openpty()` + `fork()` + `TIOCSCTTY` | Android |
| Linux 模拟 PTY | iSH | `/dev/ptmx` → emulated `tty` structs | iOS (完整 Linux 用户空间) |
| 线程流 (无 PTY) | a-Shell, Blink | `ios_system` + thread-local stdio | iOS (简单命令执行) |
| 远程 PTY | mms-remote | tmux via WebSocket RPC | iOS→Mac 远程终端 |

**关键结论: iOS 没有原生 `forkpty()`。** 所有 iOS 终端要么模拟，要么绕过，要么远程。

### 2.2 渲染引擎对比

| 引擎 | 使用者 | 优势 | 劣势 |
|-----|--------|------|------|
| **hterm + WKWebView** | iSH, Blink, a-Shell | 成熟稳定，跨平台，CSS 主题 | JS bridge 延迟，内存高，滚动卡 |
| **原生 Canvas/Paint** | Termux | 低延迟，原生滚动 | 需自己实现 ANSI 解析 |
| **CoreGraphics + Metal** | SwiftTerm | 低延迟，GPU 加速可选，UIScrollView | 平台绑定 |
| **Jetpack Compose** | ConnectBot | 声明式 UI，现代 Android | Android only |

**关键结论: mms-remote 已选 SwiftTerm (原生)，是最优路径。**

### 2.3 快捷键处理模式

**修饰键 Sticky 方案 (行业共识)：**
- iOS/Android 都没有物理键盘那样的 modifier hold
- 统一用 toggle button: tap=激活(单次), long-press=锁定(持续), 再 tap=解除
- Blink 的 SmarterKeys 最完善，但注入 SystemInputAssistantView 的 hack 维护成本高
- SwiftTerm 的 `iOSAccessoryView` 最稳定，标准 UIInputView accessory bar

**转义序列表 (全平台通用)：**
```
方向键:  ↑ \x1b[A   ↓ \x1b[B   → \x1b[C   ← \x1b[D
功能键:  F1 \x1bOP  F2 \x1bOQ  F3 \x1bOR  F4 \x1bOS
          F5 \x1b[15~ F6 \x1b[17~ ... F12 \x1b[24~
编辑键:  Home \x1b[H  End \x1b[F  PgUp \x1b[5~ PgDn \x1b[6~
Ctrl:    Ctrl+A-Z = 1-26, Ctrl+Space = 0, Ctrl+[ = 27
修饰组合: \x1b[1;5C = Ctrl+Right (5 = Ctrl 编码)
```

**xterm 修饰键编码表：**
| 组合 | CSI 参数值 |
|------|-----------|
| (无) | — |
| Shift | 2 |
| Alt | 3 |
| Shift+Alt | 4 |
| Ctrl | 5 |
| Shift+Ctrl | 6 |
| Alt+Ctrl | 7 |
| Shift+Alt+Ctrl | 8 |

**Kitty Keyboard Protocol (现代方案，SwiftTerm 已支持)：**
```
CSI unicode-key-code:alternate-key-codes ; modifiers:event-type ; text-as-codepoints u
modifier: shift=0b1(编码2), alt=0b10(编码3), ctrl=0b100(编码5), 值=bitmask+1
```

---

## 三、mms-remote 现状分析

### 3.1 已有能力

| 组件 | 文件 | 状态 |
|-----|------|------|
| SwiftTerm v1.11.2 | Package.resolved | 已集成 |
| Snapshot 渲染 | `SwiftTermTerminalView.swift` (219行) | 可用 |
| Stream 渲染 | `SwiftTerminalCanvasView.swift` (287行) | 可用 |
| 基础快捷键栏 | TerminalHubView / SwiftTerminalHubView | Esc/Tab/Ctrl-C/D/Z/方向键 |
| RPC 层 | `CodexService+Terminal.swift` (450行) | 完整 (list/create/input/resize/stream) |
| 模型层 | `TerminalModels.swift` (715行) | 完整 |
| Bridge | `terminal-hub.js` + `tmux-adapter.js` | 完整 |

### 3.2 缺失能力

| 缺失 | 影响 | 优先级 |
|-----|------|-------|
| SwiftTerm renderer 被禁用 (`false &&`) | TerminalHubView 仍用 snapshot polling | **P0** |
| 无 sticky modifier 状态管理 | Ctrl 只能单次触发，Alt 不可用 | **P0** |
| `ManagedTerminalKey` 缺 F1-F12 | 功能键不可用 | **P1** |
| 无 Alt/Meta 修饰键 | Vim/Emacs 快捷键受限 | **P1** |
| 无外接键盘检测 | 蓝牙键盘体验差 | **P1** |
| 无设备自适应布局 | iPad 和 iPhone 共用同一布局 | **P2** |
| 无主题/颜色配置 | 只有默认暗色 | **P2** |
| 无多 pane 分屏 | 一次只能看一个 pane | **P3** |

---

## 四、复用方案 — 四阶段实施

### Phase 1: 启用 SwiftTerm 渲染器 (1-2 天)

**改动:**
1. `TerminalHubView.swift:557` — 只在验收通过后移除 `false &&` 前缀
2. 统一 snapshot 和 stream 两个 Tab 为单一 SwiftTerm 渲染路径
3. `SwiftTermTerminalView` 接受 stream 数据 (已有 `feedBytes` 接口)

**风险: 中。** SwiftTerm CanvasView 可用不等于默认路径可用；必须先验证 stream replay、foreground/background cleanup、中文输入法、英文空格、Enter、光标、ANSI 色彩、resize、无横向滚动、无乱码，再切默认。

### Phase 2: 升级快捷键系统 (2-3 天)

**目标布局:**
```
Row 1: [Esc] [Ctrl] [Alt] [Tab] [/ - ~] [↑] [↓] [←] [→]
Row 2: [F1-F5] [F6-F10] [Home] [End] [PgUp] [PgDn] [Ins] [Del]
```

**改动:**
1. 新建 `TerminalKeyboardBar.swift` — SwiftUI UIViewRepresentable
2. Sticky modifier: `isCtrlActive` / `isAltActive` boolean，tap 切换，长按锁定
3. 发送逻辑: 检查 modifier → 组合转义序列 → `sendTerminalKey()`
4. `ManagedTerminalKey` 扩展: `.f1`~`.f12`, `.pageUp`, `.pageDown`, `.insert`, `.delete`
5. Alt 修饰: Option-letter → `\x1b` + letter

### Phase 3: 外接键盘 + 设备适配 (1-2 天)

**改动:**
1. 外接键盘检测 — 监听 `UIKeyboardFrameEndUserInfoKey`，`height > 116` = 硬件键盘
2. 蓝牙键盘 modifier — 合并 `UIKeyCommand.modifierFlags` 与 sticky state
3. iPad 布局 — 横屏两行，竖屏压缩一行
4. Caps Lock 重映射 — 用户可选 Esc 或 Ctrl (Vim/Emacs)

### Phase 4: 可选增强

| 增强 | 参考 | 工作量 |
|-----|------|-------|
| Metal GPU 渲染 | SwiftTerm `MetalTerminalRenderer` | 1 天 |
| 鼠标事件跟踪 | Termux mouse mode | 2 天 |
| Kitty Keyboard Protocol | SwiftTerm `KittyKeyboardProtocol.swift` | 1 天 |
| 多 pane 分屏 | 无直接参考 | 3-5 天 |

---

## 五、架构决策记录

| 决策点 | 选择 | 理由 |
|-------|------|------|
| 渲染引擎 | **SwiftTerm (原生)** | 已集成；延迟低；滚动流畅；Metal 可选 |
| 快捷键栏 | **自建 SwiftUI** | 行业共识: 键盘扩展无法直连 terminal 数据流 |
| 修饰键模型 | **2-State Toggle + 长按锁定** | Termux/SwiftTerm 验证，比 3-state 更直觉 |
| PTY 策略 | **保持远程 tmux** | 远程终端是项目核心设计 |
| Bridge 协议 | **复用现有 RPC** | `terminal/input` 已支持 key/text/data 三模式 |

---

## 六、关键参考源码索引

| 项目 | 关键文件 | 用途 |
|-----|---------|------|
| Termux | `ExtraKeysConstants.java` | 键定义、显示映射、别名 |
| Termux | `ExtraKeysView.java` | 键盘渲染、modifier 状态管理 |
| Termux | `KeyHandler.java` | 转义序列表、修饰键编码 |
| Blink | `SmarterKeys/KBLayout.swift` | 设备自适应键盘布局 |
| Blink | `SmarterKeys/KBKeyValue.swift` | 键值定义 |
| Blink | `SmarterKeys/KBProxy.swift` | iPad toolbar 注入 |
| Blink | `KBTracker.swift` | 硬件键盘检测 |
| SwiftTerm | `iOS/iOSAccessoryView.swift` | 键盘工具栏 (最稳方案) |
| SwiftTerm | `iOS/iOSKeyboardView.swift` | 自定义全键盘 |
| SwiftTerm | `KittyKeyboardProtocol.swift` | Kitty 协议支持 |
| iSH | `app/LinuxPTY.c` | iOS PTY 桥接 |
| iSH | `fs/pty.c` | Linux PTY 模拟内核 |
| ConnectBot | `termlib/.../KeyboardHandler.kt` | VTerm 键映射 |
| ConnectBot | `termlib/.../ModifierManager.kt` | 修饰键状态机 |
| iTerm2 | `VT100Output.m` | 转义序列生成表 |
| iTerm2 | `iTermStandardKeyMapper.m` | 键→序列映射 |

---

## 七、结论

mms-remote 的终端模块方向正确。SwiftTerm 已集成、stream 模式已跑通、RPC 层完整。

**核心差距在两处：**
1. SwiftTerm 渲染器被 `false &&` 硬禁用
2. 快捷键栏只有基础键，缺 modifier sticky state / F-keys / Alt

**Phase 1+2 覆盖 80% 使用场景，Phase 3 补齐外接键盘体验。** 当前优先级不是重新造 PTY，而是把远程 tmux stream + SwiftTerm renderer 打磨到 iTerm2/Ghostty 级别的显示和输入体验。hterm/WebView 可保留为 research fallback，本地 PTY 与键盘扩展不应作为主线。
