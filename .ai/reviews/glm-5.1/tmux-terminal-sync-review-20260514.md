# tmux-terminal-sync Review - Tmux Terminal Sync & Multi-Backend

- Date: 2026-05-14
- Reviewer: glm-5.1
- CLI: claude-code
- Started: 2026-05-14T15:12:00Z
- Completed: 2026-05-14T15:25:00Z
- Duration: ~13 min

## Overall Verdict

PASS_WITH_NOTES

## Blocking Findings

- none

## Non-Blocking Findings

- PACK-1: LICENSE is standard Apache 2.0 boilerplate. Copyright notice at line 189 still has placeholder `[yyyy] [name of copyright owner]` unfilled. Standard practice is to fill these before first public release. Low urgency for initial commit but should be resolved before any public distribution.

- PACK-2: Pack scope mismatch. Title and summary describe tmux terminal sync features (tmux transport, multi-client relay, iOS terminal renderer), but commit `6e1f7a0` is the initial commit containing only the LICENSE file. The pack's `changed_files: ["LICENSE"]` is accurate, but the scope description does not reflect the actual commit content. Future packs should align milestone scope with actual diff.

- PACK-3: Repo has a `NOTICE` file at root, which is appropriate for Apache 2.0 (Section 4d). No issues there.

## Boundary Check

- No out-of-scope files changed: yes. Commit touches only `LICENSE`, matches pack's `changed_files`.
- No forbidden external actions: yes. Initial commit, no external side effects.
- Validation evidence reviewed: yes. No validation steps recorded in pack (`validation: []`).

## Review Questions

1. **Does this change satisfy the declared scope without opening non-goal boundaries?**
   The changed files are within scope (LICENSE only). The pack's narrative scope is broader than the actual commit, which is just an initial LICENSE addition. No boundary violations in the code itself.

---

## Plan Assessment (PLAN.md — Tmux Terminal Sync & Multi-Backend)

Based on full codebase inspection: `bridge.js` (71.9K), `codex-transport.js` (9.0K), `relay/relay.js`, and iOS app structure (47 service files, 21 model files).

### Architecture Direction: Correct

Transport abstraction is clean. `codex-transport.js` defines `send/onMessage/onClose/onError/onStarted/shutdown` — new transport implements same interface. E2EE layer (`secure-transport.js`) encrypts envelopes, payload-agnostic. "Add parallel transport, don't refactor" is the right call. Phase ordering (relay → transport → iOS → integration → discovery) is logical.

### Critical Barriers

**BARRIER-1: tmux prerequisite — plan's biggest untested assumption**

Plan assumes user runs tmux. User's actual request: "手机上能看到我电脑上所有终端窗口". If user runs Terminal.app / iTerm2 native windows (not tmux), the entire plan is non-functional. No fallback for non-tmux terminals. This needs confirmation before any implementation starts.

**BARRIER-2: iOS terminal renderer — plan is toy-grade**

Plan proposes SwiftUI `ScrollView` + `AttributedString` (~300 lines). This cannot handle:
- VT100/VT220 state machine (cursor positioning, screen clear, scroll regions)
- Full-screen apps (vim, htop, nano — screen refresh, not line append)
- Character grid rendering (plan uses scrollable text list)

Plan says "v1 strip all ANSI, v2 add color". But stripped ANSI + no cursor positioning = vim/htop completely broken. For line-by-line shell output (ls, git, echo) it barely works. For interactive terminal use it fails.

**Recommendation**: Use [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) (iOS-native VT100 terminal emulator) instead of hand-rolling. Reduces glue code to ~200 lines while getting full terminal fidelity.

**BARRIER-3: tmux granularity — session vs pane**

Plan models `listSessions / attachSession`. But tmux structure is `session → window → pane`. User wants "all terminal windows" which means all panes across all windows. Plan's `capturePane(name)` operates at session level — multi-pane windows only show the active pane. Pane-level addressing (`tmux capture-pane -t session:window.pane`) is missing.

**BARRIER-4: iOS keyboard input — severely underestimated**

Plan mentions "keyboard input → JSON-RPC tmux/input" in one sentence. iOS has no physical Escape / Ctrl / Alt / arrow keys. Required:
- Custom input bar with modifier keys (Ctrl, Alt, Esc)
- Arrow key sequences (CSI A/B/C/D)
- Tab completion, Ctrl+C interrupt, Ctrl+D EOF
- Full key sequence mapping to CSI/SS3 escape codes

This is not 100 lines. Reference: Termius uses a dedicated terminal keyboard extension (~500+ lines).

### Code-Level Risks

| Risk | Plan Estimate | Reality | Gap |
|------|-------------|---------|-----|
| `bridge.js` tmux routing | +50 lines | +150-200 lines | 3-4x. Adding tmux dispatch to 72K monolith with complex message routing chain, plus session lifecycle management |
| iOS terminal renderer | ~300 lines | 1000+ lines (or ~200 lines with SwiftTerm) | Plan self-rolling is 3x underestimate. SwiftTerm eliminates the gap |
| iOS keyboard input | implicit in ~100 lines | ~300-500 lines | Dedicated input bar with modifier key support |
| Total new code | ~750 lines | 2000-3000 lines | 3-4x underestimate |
| `node-pty` compilation | low risk | medium risk | Native addon, breaks on any major Node version upgrade. Plan's fallback to `child_process + tmux capture-pane polling` is viable but 100ms polling = noticeable typing lag |

### What the Plan Gets Right

1. Phase ordering: relay multi-client → tmux transport → iOS renderer → mode switching → discovery. Each phase is independently testable.
2. Leaving E2EE / QR pairing / codex-transport untouched. Correct — these are fully decoupled.
3. Relay multi-client change IS ~10 lines. Removing the eviction loop at `relay.js:133-148` is the core change. Backpressure implications are minor for the initial version.
4. Verification criteria mostly cover user's core scenarios (see all sessions, bidirectional sync, create new).

### Recommended Plan Amendments

1. **Add prerequisite check**: Confirm user runs tmux daily. If not, plan needs fundamental rewrite (e.g., custom PTY multiplexer, or screen-capture based approach).
2. **Replace SwiftUI ScrollView renderer with SwiftTerm**: Full VT100 emulation, proper character grid, built-in keyboard handling. Saves implementation time and delivers production-quality terminal.
3. **Extend tmux model to pane granularity**: `listSessions` → `listWindows` → `listPanes`. Add `capturePane(session, window, pane)` addressing. User expects per-pane view, not per-session.
4. **Add iOS terminal input bar design**: Dedicated input component with modifier key row (Ctrl/Alt/Esc/Tab/↑/↓/←/→). Budget ~300-500 lines.
5. **Revise `bridge.js` estimate to 150-200 lines**: tmux message routing, session lifecycle, error recovery in a 72K dispatch chain.
6. **Consider `node-pty` alternative**: `child_process.spawn('tmux', ['attach', ...])` with pipe I/O is simpler and avoids native compilation. Only need `node-pty` if true PTY semantics (raw mode, signal handling) are required for the attach use case.

### Verdict on Plan Credibility

**Direction is sound, implementation estimates are optimistic by 3-4x, and two critical assumptions (tmux usage, terminal rendering approach) need correction before implementation begins.** The plan will produce a working prototype for line-by-line shell interaction, but will not deliver "手机看到所有终端窗口，像终端一样用" without the amendments above.
