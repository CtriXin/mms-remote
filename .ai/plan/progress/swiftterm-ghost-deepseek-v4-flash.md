# SwiftTerm Ghost Independent Review — deepseek-v4-flash

Timestamp: 2026-05-16
Agent: deepseek-v4-flash
Model: deepseek-v4-flash
Scope: research/docs-only
Status: analysis-complete, independent

---

## Critical Finding Missed By Prior Agents

**The quarantine logic described in `Docs/swiftterm_ghost_analysis.md` does NOT exist in current codebase.** `MMSStreamTerminalView` (SwiftTerminalCanvasView.swift:524-623) has:

- NO `addSubview()` override
- NO `quarantineSwiftTermCaretViews()`
- NO `quarantineSwiftTermCaretView()`
- NO `isSwiftTermCaretView()`
- NO `flushDisplayAfterOutboundInput()`
- NO `updateMobileCursorOverlay()`
- NO `draw()` override

Prior agents (mimo-v2.5-pro, Peirce, Kierkegaard) analyzed code that references quarantine methods at lines 957/1116-1139. **These lines do not exist in current `1.7.53 build 91`.** All quarantine logic was either reverted or never merged.

This changes root cause analysis: ghost persists WITHOUT any app-level race with quarantine. CaretView follows standard SwiftTerm lifecycle unobstructed.

---

## Root Cause Ranking

### H1 (~60%): CaretView glyph overlay — `tracksFocus` behavior + `setText()` every `updateDisplay()`

**Mechanism (verified in current code):**

1. User input → `feed()` → `queuePendingDisplay()` → 16ms throttle → `updateDisplay()` (AppleTerminalView.swift:1455)
2. `updateDisplay()` calls `updateCursorPosition()` first (line 1457)
3. `updateCursorPosition()` (line 1505-1531):
   - Line 1516-1517: `else if terminal.cursorHidden == false && caretView.superview != self { addSubview(caretView) }`
   - Line 1529: `caretView.frame.origin = CGPoint(...)` — positions CaretView at cursor
   - Line 1530: `caretView.setText(ch: buffer.lines[vy][buffer.x])` — creates CTLine, `setNeedsDisplay(bounds)`
4. `CaretView.draw()` (iOSCaretView.swift:124-132):
   ```swift
   drawCursor(in: context, hasFocus: tracksFocus ? (superview?.isFirstResponder ?? true) : true)
   ```
5. `CaretView.drawCursor()` (CaretView.swift:12-67):
   - For steadyBlock/blinkBlock: fills entire bounds with `bgColor`, then `CTFontDrawGlyphs` renders character glyph on top
   - The glyph uses `caretTextColor ?? terminal.nativeForegroundColor` — rendered in cursor foreground color

**Why ghost appears:** CaretView renders the character glyph at cursor position using `CTFontDrawGlyphs` with cursor colors (inverse/filled block). This overlays the terminal's own character rendering at the same position. The visual result is a "double character" — one from terminal buffer, one from CaretView overlay — with different colors creating a shadow effect.

**When `tracksFocus = false` (if set in previous version):** `hasFocus` always `true` → always draws filled block with glyph, even when view not first responder. This would make ghost persistent.

**When `tracksFocus = true` (default, current):** Only draws filled block when `isFirstResponder`. Ghost appears only during input (when keyboard active). After dismissal, CaretView draws hollow outline (no glyph) → ghost disappears.

**Evidence:**
- Ghost is "character shaped" — matches `CTFontDrawGlyphs` rendering
- Tab switch clears ghost → full view rebuild discards stale composited layers
- Ghost appears on input → exactly the feed→updateDisplay→updateCursorPosition→setText path
- Current code has NO quarantine → CaretView stays in view tree uninterrupted

### H2 (~25%): iOS `updateCursorPosition()` coordinate system vs `feedPreservingScroll` offset restoration

**Mechanism:**
iOS `updateCursorPosition()` (AppleTerminalView.swift:1522-1524):
```swift
let offset = (cellDimension.height * (CGFloat(buffer.y+(buffer.yBase))))
let lineOrigin = CGPoint(x: 0, y: offset)
```
iOS uses **absolute** `buffer.y + buffer.yBase` (content coordinate space, not viewport).

Compare macOS (line 1526-1527):
```swift
let lineOrigin = CGPoint(x: 0, y: frame.height - offset)
```
macOS adjusts for `(frame.height - offset)` — correctly positions within visible frame.

This means on iOS, CaretView position is calculated in **unclipped content coordinates**. If `contentOffset.y` changes between `updateCursorPosition()` and the actual display cycle commit, CaretView appears at wrong visual position.

`feedPreservingScroll()` (SwiftTerminalCanvasView.swift:544-558) restores `contentOffset` to preserved scroll position AFTER feed completes but BEFORE `updateDisplay()` fires (16ms async). This creates a window where CaretView frame was calculated for one scroll position but composited at another.

**Evidence:**
- SwiftTerm iOS path has explicit TODO for this area (AppleTerminalView.swift:1488-1489)
- Ghost more likely when user has manually scrolled up (feedPreservingScroll activates)
- `setContentOffset` override in MMSStreamTerminalView (line 561-575) further manipulates scroll

### H3 (~10%): Bridge replay `\r\n` appending + `normalizedOutputBytes` cursor position drift

`terminal-stream-hub.js:126`: always appends `\r\n` to replay capture. If content already has trailing newline, this adds a blank line that shifts cursor. Combined with iOS `normalizedOutputBytes` which adds CR before LF, may produce double CRLF.

**Evidence:**
- `normalizeTerminalOutputBuffer` appends `\r\n` unconditionally
- `viewport replay: true` in stream start — replay runs on every connection
- Replay ghost differs from live ghost but could amplify CaretView artifact

**Counter-evidence:**
- Ghost also appears during live streaming, not just after replay
- CRLF normalization fixed garble — reverting would regress

### H4 (~5%): Dirty-rect / contentOffset coordinate mismatch (Peirce hypothesis)

`drawTerminalContents()` iOS path (AppleTerminalView.swift:1037-1053) already uses `contentOffset.y / cellHeight` for firstRow/lastRow computation. `updateDisplay()` calls `setNeedsDisplay(bounds)` (entire visible bounds). Current code does NOT have the dirty-rect issue Peirce hypothesized.

---

## Access Control Constraint (Missed By Prior Agents)

**`CaretView` class is `internal` to SwiftTerm module** (iOSCaretView.swift:16):
```swift
class CaretView: UIView {  // no 'public' → internal
```

**`caretView` property is likely `internal`** — referenced throughout AppleTerminalView.swift but never declared `public`. Neither `CaretView` type nor `caretView` property is directly accessible from `CodexMobile` app module.

**Impact:** The `view === caretView` comparison proposed by mimo-v2.5-pro will NOT compile:
```swift
// WILL NOT COMPILE — 'caretView' inaccessible
override func addSubview(_ view: UIView) {
    if let caretView = self.caretView, view === caretView {  // ❌
        return
    }
    super.addSubview(view)
}
```

**Workaround:** String-based type check:
```swift
override func addSubview(_ view: UIView) {
    if String(describing: type(of: view)) == "CaretView" {
        return
    }
    super.addSubview(view)
}
```

Or use Objective-C runtime:
```swift
if view.isKind(of: NSClassFromString("SwiftTerm.CaretView") ?? UIView.self) {
    return
}
```

---

## Minimal Diagnostic (docs-only, no code commit)

### Diagnostic A: Add CaretView interception log (temporary debug)

```swift
override func addSubview(_ view: UIView) {
    if String(describing: type(of: view)) == "CaretView" {
        NSLog("[GHOST] CaretView addSubview blocked. frame=%@", NSCoder.string(for: view.frame))
        // return  ← uncomment to test fix
    }
    super.addSubview(view)
}
```

Build, install, observe console. Confirms whether CaretView addSubview is the path.

### Diagnostic B: Log CaretView draw frequency

```swift
// In MMSStreamTerminalView
override func layoutSubviews() {
    super.layoutSubviews()
    // Check if CaretView exists in hierarchy
    let hasCaret = subviews.contains(where: { String(describing: type(of: $0)) == "CaretView" })
    if hasCaret {
        NSLog("[GHOST] CaretView in hierarchy. contentOffset=%@", NSCoder.string(for: contentOffset))
    }
}
```

---

## Minimal Real Patch

### Patch 1 (primary, cleanest): Intercept CaretView in `addSubview`

File: `SwiftTerminalCanvasView.swift` — `MMSStreamTerminalView` class

```swift
override func addSubview(_ view: UIView) {
    if String(describing: type(of: view)) == "CaretView" {
        return  // Prevent CaretView from entering view tree, eliminating glyph overlay
    }
    super.addSubview(view)
}
```

**Pros:**
- Stops CaretView glyph at source — no CTLine, no CTFontDrawGlyphs, no overlay
- No timing/race issues — synchronous return before CaretView enters hierarchy
- Does NOT affect cursor appearance if app provides its own cursor overlay
- Reversible — remove override = restore SwiftTerm default

**Cons:**
- Relies on string-based type check (fragile if SwiftTerm renames CaretView)
- If cursor becomes invisible, users may complain (verify with mobileCursorView)
- SwiftTerm's `updateCursorPosition()` still runs `setText()` but CaretView won't render

**Alternative (more robust type check):**
```swift
private static let isCaretView: (UIView) -> Bool = {
    let cls = NSClassFromString("SwiftTerm.CaretView") ?? UIView.self
    return { $0.isKind(of: cls) }
}()
```

### Patch 2 (defensive): Invalidate CaretView frame rect on scroll

If Patch 1 is applied, this is insurance. If cursor still appears via other path:

```swift
override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
    // Force redraw of old CaretView area before scroll offset changes
    setNeedsDisplay()
    super.setContentOffset(contentOffset, animated: animated)
}
```

### Patch 3 (Bridge): Conditional trailing CRLF in viewport replay

File: `terminal-stream-hub.js` — `replay()` function

```js
// Only append \r\n if content doesn't already end with line terminator
let content = `${capture.content || ""}`;
const hasTrailingNewline = content.endsWith("\n") || content.endsWith("\r");
const normalized = normalizeTerminalOutputBuffer(
  Buffer.from(hasTrailingNewline ? content : `${content}\r\n`, "utf8")
);
```

---

## What Prior Agents Got Wrong

### mimo-v2.5-pro

| Claim | Reality |
|-------|---------|
| "CaretView addSubview interception with `self.caretView`" | Won't compile — `caretView` is internal to SwiftTerm module |
| "Quarantine race at 16ms" | Quarantine code does NOT exist in current codebase |
| "85% probability" | Overconfident — didn't verify actual code |

### Peirce

| Claim | Reality |
|-------|---------|
| "Dirty-rect vs contentOffset mismatch" | iOS already uses `contentOffset.y` (line 1045). Hypothetical issue already resolved |
| "visibleRect clearing needed" | iOS uses `setNeedsDisplay(bounds)` — full bounds redraw |

### Kierkegaard

| Claim | Reality |
|-------|---------|
| "Bridge replay/live order risk ~5%" | Correct that it's low probability. But diagnostic suggestions (sha256 per chunk) are overengineered for visual-only ghost |

---

## My Conclusions

| Question | Answer |
|----------|--------|
| Highest prob root cause | CaretView glyph overlay via `updateCursorPosition()` → `setText()` → `CTFontDrawGlyphs` — character glyph composited on top of terminal buffer creates "double character" visual (H1, ~60%) |
| Problem layer | iOS SwiftTerm CaretView compositing |
| What previous agents missed | (1) Quarantine code absent from current codebase; (2) `caretView` is internal to SwiftTerm — can't access from app; (3) iOS CaretView uses absolute content coordinates, not viewport-relative |
| Must not repeat | Quarantine, full-replay-as-fix, hidden input proxy, RunLoop drain, SwiftTerm disable |
| Minimal diagnostic | `addSubview` interception with type string check + NSLog |
| Minimal real patch | `addSubview` override returning false for CaretView (string type check) |
| Second order patch | `feedPreservingScroll` caret invalidation |
| Risk | String-based type check fragile; cursor invisibility possible if no overlay exists |
| Validation | Build + install to song's iPhone, test input/cursor/scroll/pane switch |
