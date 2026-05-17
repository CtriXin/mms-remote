# SwiftTerm Ghost External Review — gpt-5

Timestamp: 2026-05-16T23:44:00-04:00
Owner: codex
CLI: codex
Model: gpt-5
Task ID: swiftterm-ghost-seventh-agent-20260516
Scope: research/docs-only; no implementation, no build, no tests
Status: completed
Next Action: Use this as the seventh-agent view for the synthesis in `Docs/swiftterm_ghost_agent_review_summary.md`.

## One-Line Conclusion

The current ghost/影子 should be handled as a SwiftTerm iOS caret/render-layer invalidation bug first, not as a Bridge byte-order bug; the next code pass should validate with cursor/draw instrumentation and try a bar-cursor A/B before any heavier SwiftTerm fork patch.

## Background Recovered

- Current device anchor: iOS `1.7.53 build 91` on `song的iPhone`.
- Fixed before this review: blank startup, `cd` display/order problem, garble/乱码.
- Still unresolved: visual ghost/影子 after SwiftTerm input; switch/refresh/full replay clears it.
- The symptom is visual-only: existing notes repeatedly say tmux/SwiftTerm buffer content is correct.
- Current wrapper state matters: `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift:524` through `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift:623` has no `addSubview` interception, no `quarantineSwiftTermCaretViews`, no `draw` override, no hidden input proxy, and no mobile cursor overlay.

## Current Code Evidence I Verified

| Evidence | Path | Impact |
|---|---|---|
| `MMSStreamTerminalView` only keeps scroll/font/paste behavior | `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift:524` | Old quarantine-based analysis is stale for the current codebase. |
| SwiftTerm iOS `draw(_:)` clears only `dirtyRect` | `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/iOS/iOSTerminalView.swift:1288` | If dirty rect is narrowed or old cursor area is not invalidated, stale pixels can survive. |
| iOS row calculation uses `contentOffset.y`, not `dirtyRect.minY` | `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift:1037` | Peirce-style dirtyRect/row mismatch is partially mitigated, but contentOffset/yDisp consistency still matters. |
| `updateDisplay()` moves cursor before redraw and can return early | `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift:1455` | Cursor can move even when `setNeedsDisplay(bounds)` is not called because `getUpdateRange()` is nil. |
| `updateCursorPosition()` adds/moves `CaretView` and calls `setText` | `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift:1505` | This is the high-frequency path after input echo. |
| `CaretView` is module-internal and independent layer | `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/iOS/iOSCaretView.swift:16` | App code cannot safely compare against `self.caretView`; string/runtime detection only. |
| Block cursor draws a full glyph via `CTFontDrawGlyphs` | `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/CaretView.swift:46` | This is the visual source material for double-character ghost. Bar/underline does not draw that glyph. |

## Agent Views Classified

| Category | Agents | Summary |
|---|---|---|
| SwiftTerm renderer/caret/compositor is primary | deepseek-v4-flash, qwen3.6-plus, kimi-k2.6, claude-opus-4.7, mimo-v2.5-pro, partly glm-5.1 | Most agents converge on `CaretView` glyph + iOS compositor/invalidation as the main root. |
| Dirty rect / contentOffset / source-level invalidation | Peirce, glm-5.1, claude-opus-4.7 | SwiftTerm iOS path has TODO-quality invalidation; old/new caret frame or visible viewport must be invalidated more reliably. |
| Bridge replay/live/input ordering | Kierkegaard, partly kimi/deepseek as low-probability fallback | Useful as telemetry only if renderer hypothesis fails; not the first patch target because switching UI clears ghost. |
| Current-code correction | deepseek-v4-flash, qwen3.6-plus, kimi-k2.6, claude-opus-4.7, glm-5.1 | The old quarantine/input-proxy docs reference removed code and should not be used as direct patch instructions. |

## My Probability Ranking

1. **65% — SwiftTerm iOS `CaretView` block-cursor glyph + layer/compositor stale invalidation.** The artifact is character-shaped, appears after input echo, disappears after view/layer rebuild, and block cursor explicitly draws glyphs.
2. **20% — SwiftTerm iOS redraw coverage gap.** `updateDisplay()` can move the cursor then return without `setNeedsDisplay`, while `iOSTerminalView.draw` clears only the delivered `dirtyRect`.
3. **10% — `contentOffset.y` / `displayBuffer.yDisp` drift around `feedPreservingScroll`.** This can amplify dirty rect problems, especially when not at bottom, but cannot explain all bottom-input cases alone.
4. **5% — Bridge bytes/order/replay tail.** Worth tracing only after renderer checks; real duplicate bytes would remain in buffer and would not disappear just by switching views.

## What I Would Not Do Next

- Do not disable SwiftTerm.
- Do not use full replay/full refresh as the final fix; it masks ghost but creates the unacceptable flash.
- Do not retry `1.7.49/87` RunLoop/default-mode drain; handoff says it broke `cd`/`pwd` echo/order.
- Do not reintroduce hidden input proxy + cursor quarantine as the main solution; current code removed it and prior attempts did not close the bug.
- Do not set startup stream to pure `replay: false`; it caused blank startup.
- Do not blind-upgrade SwiftTerm latest `602be53` until the Metal Toolchain build blocker is solved.
- Do not start with Bridge CR/LF/dedupe churn unless renderer instrumentation disproves the visual-layer hypothesis.

## My Recommended Treatment

### Phase 1 — Evidence Build, No Behavior Change Except Logs

Add DEBUG-only instrumentation in `MMSStreamTerminalView`:

- `override func addSubview(_:)`: log only when class name contains `CaretView`, include frame and short call stack.
- `override func setNeedsDisplay(_:)` and `override public func draw(_:)`: log rect, bounds, contentOffset, contentSize.
- `feedPreservingScroll`: log `contentOffset.y`, `displayBuffer.yDisp`, and cellHeight-derived delta; do not log user input or payload.

Goal: decide whether old cursor rect is not invalidated, dirtyRect is narrowed, or contentOffset/yDisp diverges.

### Phase 2 — Lowest-Risk A/B Mitigation

Try app-level cursor style A/B first:

```swift
terminalView.getTerminal().options.cursorStyle = .steadyBar
terminalView.updateCaretView()
```

Reason: block cursor is the only SwiftTerm cursor style that draws a full character glyph; bar/underline preserves a visible cursor while removing the glyph overlay source. This is safer than blocking `CaretView` because current code has no replacement cursor overlay.

If this removes the ghost, ship it as the default or as a `Terminal Settings` option such as `Cursor style: Bar / Block`, defaulting to Bar for SwiftTerm live renderer.

### Phase 3 — Root Fix If Block Cursor Must Stay

Prepare a durable SwiftTerm-source patch, not a transient SPM checkout edit:

- Fork/pin current working SwiftTerm revision, not latest `602be53` until Metal Toolchain is solved.
- In `AppleTerminalView.updateCursorPosition()`, invalidate old and new caret frame union before/after moving `CaretView`.
- Wrap `caretView.frame.origin` movement in disabled Core Animation actions.
- In iOS `draw(_:)`, clear full visible bounds or at least old/new caret rect before drawing.

This is the real path if product wants block cursor fidelity without a bar-cursor workaround.

### Phase 4 — Bridge Trace Only If Renderer Path Fails

If bar cursor plus draw/caret logs do not explain the issue, then apply Kierkegaard-style trace:

- Bridge: seq, replay/live phase, byteLength, sha8, first/last hex.
- iOS: feed seq order, byte count, sha8.
- No raw payload, no `sessionId`, no pairing token.

## Patch Ranking

| Rank | Patch | Why |
|---|---|---|
| 1 | DEBUG draw/caret/contentOffset instrumentation | Prevents another blind patch loop. |
| 2 | `.steadyBar` A/B and possible default | Minimal, compiles from app module, preserves cursor, removes glyph source. |
| 3 | `layer.setNeedsDisplay()` throttled after feed | May help tile cache, but less targeted than removing block glyph. |
| 4 | SwiftTerm fork: invalidate old/new caret frames + clear visible bounds | Best root fix, higher maintenance cost. |
| 5 | `addSubview` CaretView block | Useful as diagnostic only; risky final fix because current app has no replacement cursor and prior attempt did not settle the issue. |
| 6 | Bridge CRLF/replay changes | Low probability for this specific visual-only symptom. |

## Validation Plan For A Future Code Pass

- Do not run Xcode tests unless explicitly requested.
- Any iOS code change must bump version/build; next patch-level target from current handoff is `1.7.54 build 92`.
- Generic build:
  ```bash
  xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData-ghost-next CODE_SIGNING_ALLOWED=NO build
  ```
- Device build/install only to `song的iPhone` using the existing project commands in `.ai/plan/swiftterm-ghost-external-agent-prompt.md`.
- Manual smoke: rapid ASCII input, `ls -la`, `printf 'LONG-LINE-ABCDEFG\r\033[Kshort\n'`, scroll-not-bottom input, tab switch, app background/foreground.
- If Bridge files change, run:
  ```bash
  HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test --prefix mms-remote-bridge
  ```

## Final Position

Treat this as a SwiftTerm iOS render/cursor-layer bug with Bridge as a fallback investigation. The shortest correct path is: instrument once, try bar cursor A/B, then only fork/pin SwiftTerm for old/new caret invalidation if block cursor must remain.
