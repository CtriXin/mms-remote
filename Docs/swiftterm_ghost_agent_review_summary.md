# SwiftTerm Ghost Agent Review Summary

Timestamp: 2026-05-16T23:44:00-04:00
Owner: codex
CLI: codex
Model: gpt-5
Task ID: swiftterm-ghost-seventh-agent-20260516
Status: completed; docs-only synthesis
Related Review: `.ai/plan/progress/swiftterm-ghost-external-review-gpt-5.md`

## Conclusion First

交接文档里已经写了这个问题：`SwiftTerm` ghost/影子在 `1.7.53 build 91` 仍未解决；所有已查到的 agent review 综合后，处理方向应定为 **SwiftTerm iOS `CaretView`/renderer/compositor 问题优先，Bridge byte/order 只做后备 telemetry**。

## Where It Was Documented

| File | What It Says |
|---|---|
| `.ai/plan/current.md` | 当前真相面板明确写着 `SwiftTerm ghost remains known unresolved and documented`。 |
| `.ai/plan/handoff.md` | 记录了 `1.7.33` 到 `1.7.53` 的多轮尝试、回归与禁止方向。 |
| `.ai/plan/progress/swiftterm-ghost-multiagent.md` | 记录 Peirce/Kierkegaard 两个前置 multiagent 结论。 |
| `.ai/plan/progress/swiftterm-ghost-deepseek-v4-flash.md` | 独立指出当前代码已无 quarantine，并主张 CaretView glyph overlay。 |
| `.ai/plan/progress/swiftterm-ghost-external-review-qwen.md` | 主张 CaretView layer/glyph 残留，保留 yDisp/contentOffset 次要假设。 |
| `.ai/plan/progress/swiftterm-ghost-external-review.md` | kimi-k2.6 总结：renderer invalidation + CaretView compositor race，建议 bar cursor 或 source patch。 |
| `.ai/plan/progress/swiftterm-ghost-external-review-glm51.md` | 主张 iOS `draw(_:)` dirtyRect 清除不足 + early return，建议 full-bounds clear 或 bar cursor。 |
| `.ai/plan/progress/swiftterm-ghost-external-review-claude-opus-4.7.md` | 主张 CaretView stale tile cache，建议 instrumentation 后用 throttled invalidation / source patch。 |
| `Docs/swiftterm_ghost_analysis.md` | 主汇总文档；包含旧假设、multiagent 结果、deepseek/qwen/kimi/mimo 等摘要。 |
| `Docs/swiftterm_ghost_analysis_glm51.md` | GLM 的独立摘要。 |

## Current Known State

- 当前可用安装点：iOS `1.7.53 build 91`，设备 `song的iPhone`。
- 已修复：blank startup、`cd`/`pwd` 显示/顺序、乱码/换行问题。
- 未修复：SwiftTerm 输入后视觉 ghost/影子/双字符残留。
- 关键性质：切换/刷新/full replay 会清掉；buffer 真值正确；因此更像 visual/compositor artifact。
- 当前代码：`MMSStreamTerminalView` 只有 scroll/font/paste/key command 相关 hook，没有旧的 hidden input proxy、mobile cursor overlay、CaretView quarantine、`addSubview` override 或 `draw` override。

## Agent Classification

| Agent | Highest-Probability Root | Suggested Fix | My Classification |
|---|---|---|---|
| Peirce | SwiftTerm iOS dirty-rect/background clear vs `UIScrollView.contentOffset` | SwiftTerm source-level visibleRect/row clear; invalidate old/new caret frame | Renderer/source invalidation bucket |
| Kierkegaard | Bridge replay/live/input order remains measurable risk | seq/phase/hash trace; replayGeneration; per-pane input queue | Telemetry fallback bucket |
| mimo-v2.5-pro | `updateCursorPosition()` adds CaretView + `setText`; block glyph leaves GPU residue | Intercept `addSubview` for CaretView | Correct direction, patch risky/stale details |
| deepseek-v4-flash | CaretView glyph overlay; current code has no quarantine; `CaretView` is internal | String-based `addSubview` intercept; optional CRLF replay tweak | Strong current-code correction; final patch risky if no replacement cursor |
| qwen3.6-plus | CaretView block glyph + CoreAnimation stale layer; yDisp/contentOffset secondary | addSubview log/intercept; yDisp delta log | Renderer primary, host integration secondary |
| kimi-k2.6 | SwiftTerm invalidation + CaretView subview compositor race | Default cursor style to `.steadyBar`; source patch old-frame invalidation if block needed | Best low-risk mitigation proposal |
| glm-5.1 | `draw(_:)` clears `dirtyRect` not `bounds`; early return can skip redraw | full-bounds draw override; bar/underline fallback | Good diagnosis; app-level code sample may need access-control adjustment |
| claude-opus-4.7 | CaretView stale tile cache + iOS TODO invalidation | DEBUG instrumentation; throttled `layer.setNeedsDisplay`; source patch if needed | Best evidence-first workflow |
| gpt-5 | CaretView block glyph/compositor + redraw coverage gap; Bridge low probability | instrument once, A/B `.steadyBar`, then source-level old/new caret invalidation | Seventh-agent synthesis |

## Consensus

1. **Main layer**: SwiftTerm iOS renderer/compositor, especially `CaretView` block cursor and redraw invalidation.
2. **Why not Bridge first**: If bytes were truly duplicated, switching away/back would not remove duplicate content from the terminal buffer.
3. **Why CaretView matters**: block cursor draws a full glyph via `CTFontDrawGlyphs`; that can look exactly like a second character/shadow.
4. **Why old docs are dangerous**: early `Docs/swiftterm_ghost_analysis.md` sections reference removed code (`quarantineSwiftTermCaretViews`, hidden proxy, mobile cursor overlay). Use later appended reviews and current source instead.
5. **Why full replay is rejected**: it clears the artifact by resetting/redrawing everything, but creates visible flash and was explicitly rejected.

## Disagreements To Resolve

| Disagreement | My Resolution |
|---|---|
| `addSubview` interception as final fix | Use only as diagnostic unless a replacement cursor exists. Current code has no mobile cursor overlay, and prior handoff says this direction did not settle the bug. |
| App-level full-bounds `draw` patch | Pre-clear + `super.draw` may be feasible, but calling SwiftTerm internal `drawTerminalContents` from app module is likely not durable. Source patch is cleaner. |
| Bridge replay/CRLF changes | Keep as fallback; CR/LF changes already fixed garble but not ghost. |
| Direct SwiftTerm latest upgrade | Do not do it until Metal Toolchain/build issue is solved. Fork/pin current working revision for small patch if needed. |

## Recommended Handling Plan

### Step 1 — One Evidence Build

Add DEBUG-only logs in `MMSStreamTerminalView` for:

- `addSubview(_:)` when class name contains `CaretView`.
- `setNeedsDisplay(_:)` and `draw(_:)` rect/bounds/contentOffset.
- `feedPreservingScroll` offset, `displayBuffer.yDisp`, cellHeight-derived delta.

Do not log user payload, relay `sessionId`, pairing tokens, or raw terminal text.

### Step 2 — Lowest-Risk Product Mitigation

A/B force SwiftTerm cursor style to bar:

```swift
terminalView.getTerminal().options.cursorStyle = .steadyBar
terminalView.updateCaretView()
```

If ghost disappears or becomes effectively invisible:

- Ship bar cursor as the SwiftTerm default.
- Optionally add a settings choice: `Bar` default, `Block` advanced/experimental.
- Keep `replaysSwiftTermAfterInput = false`; do not reintroduce flash.

### Step 3 — Root Fix If Block Cursor Is Required

Create a durable SwiftTerm fork/pin against current working revision and patch:

- Invalidate old and new `CaretView` frame union in `updateCursorPosition()`.
- Disable implicit animation around `caretView.frame.origin` movement.
- Clear visible bounds or at least cursor old/new rects before drawing.
- Keep latest SwiftTerm upgrade separate until Metal Toolchain is solved.

### Step 4 — Bridge Trace Only If Needed

If the renderer path fails, add narrow seq/hash telemetry across Bridge and iOS feed:

- streamId suffix, paneId, seq, replay/live phase, byteLength, sha8, first/last hex.
- No payload and no credentials.

## Forbidden Paths

- Do not disable SwiftTerm.
- Do not use full replay/full refresh as the final fix.
- Do not retry the `1.7.49/87` RunLoop/default-mode stream drain.
- Do not restore hidden input proxy / mobile cursor overlay / CaretView quarantine as the main fix.
- Do not use startup `replay: false` live-only again.
- Do not blind-upgrade SwiftTerm latest `602be53` while Metal Toolchain is unresolved.
- Do not churn Bridge normalization before renderer evidence says Bridge is involved.

## Final Decision

下一次真正修代码时，先做 **renderer evidence build + `.steadyBar` A/B**；如果它解决，就用 bar cursor 作为最小可发方案；如果产品必须保留 block cursor，再 fork/pin SwiftTerm 做 old/new caret invalidation 和 iOS draw clearing。Bridge 只在这些都失败后进入 telemetry 排查。
