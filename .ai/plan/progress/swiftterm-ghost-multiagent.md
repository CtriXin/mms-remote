# Progress — SwiftTerm Ghost Multiagent

ID: swiftterm-ghost-multiagent
Title: SwiftTerm iOS visual ghost unresolved investigation
Started: 2026-05-16T23:13:23-04:00
Updated: 2026-05-16T23:21:34-04:00
Owner: codex
CLI: codex
Model: gpt-5
Status: multiagent-completed-recorded; no more blind local patches
Next Action: Continue v2 work unless user asks for a dedicated ghost pass. If returning to ghost, use source-level SwiftTerm draw diagnostic plus Bridge/iOS stream trace.

## Current Device Point

- iOS `1.7.53 build 91` installed/launched on `song的iPhone`.
- Fixed regressions: blank startup, `cd` display issue, garble/乱码.
- Remaining issue: SwiftTerm visual ghost/影子 after input; switching/refreshing clears it.

## Agent Results

- `Peirce` (`019e33ec-f229-7f90-b8fa-766d3d859ac2`): Peirce conclusion: most likely root is SwiftTerm iOS renderer dirty-rect/background clear vs UIScrollView.contentOffset coordinate mismatch; CaretView may amplify but wrapper-level quarantine is not sufficient. Suggested source-level draw visibleRect/row clear plus old/new caret invalidation; app wrapper should only preserve scroll when user manually scrolled.
- `Kierkegaard` (`019e33ed-0b05-7fa0-97ff-feda2c0249aa`): Kierkegaard conclusion: still audit Bridge/replay/live/input ordering. Viewport replay is not raw terminal state; live-during-replay heuristic can leak duplicate tails; input sends are independent Tasks without per-pane queue. First diagnostic should trace stream seq/phase/hash and iOS feed order; patch directions include avoiding final replay CRLF, adding replayGeneration/phase, and per-pane input queue.

## Next Ghost Pass, If Any

- Diagnostic: trace Bridge stream seq/phase/hash and iOS feed order.
- Patch candidate: SwiftTerm source-level iOS draw visibleRect/row clear and old/new caret invalidation.
- Version: any iOS code change must bump to next version/build and install only to `song的iPhone`.

## Guardrails

- Do not disable SwiftTerm.
- Do not use replay/full-screen refresh as final fix.
- Do not retry `1.7.49/87` RunLoop/default-mode drain.
- Do not reintroduce hidden input proxy + cursor quarantine as the main fix.
- Do not set startup stream `replay: false` only; it caused blank startup.
- Do not upgrade SwiftTerm latest until Metal Toolchain issue is solved.
- No Xcode tests unless user explicitly asks.
