# tmux-terminal-sync Review - Tmux Terminal Sync & Multi-Backend

- Date: 2026-05-14
- Reviewer: mimo-v2.5
- CLI: claude-code
- Started: 2026-05-14
- Completed: 2026-05-14
- Duration: <5m

## Overall Verdict

BLOCKED

## Blocking Findings

**BLOCK-1: Commit does not match pack scope**

Commit `6e1f7a0` is the repo's initial commit. It adds exactly one file: `LICENSE` (Apache 2.0, 201 lines). No tmux code, no transport layer, no relay changes, no iOS changes. The pack's summary and review questions describe a feature that does not exist in this commit.

**Recommendation:** Point the pack at the commit(s) that actually contain the tmux-terminal-sync feature code, or create a separate pack for the initial-commit milestone.

**BLOCK-2: PLAN has unresolved architecture blocker — tmux single-attach limitation**

PLAN scenario 4 states "Mac 和手机的操作互不影响，双向实时同步". tmux sessions only allow **one attached client** at a time. When the phone attaches via node-pty, the Mac terminal detaches (shows `[detached]`). The reverse is also true.

PLAN does not answer: **what happens to the Mac terminal when the phone attaches?**

Two possible solutions, neither discussed in PLAN:
- **A:** Mac side becomes read-only observer via `tmux capture-pane` polling (Mac can't type)
- **B:** Use `tmux -CC` (control mode) or custom socket so each side connects to a different socket (requires tmux config changes, invasive)

This is a hard blocker for the "bidirectional concurrent control" requirement. PLAN must resolve this before Phase 2.

**BLOCK-3: node-pty + tmux double PTY nesting is wrong architecture**

PLAN Phase 2 proposes `node-pty` to spawn `tmux attach`. This creates: node-pty creates PTY → runs `tmux attach` inside → tmux binds to its own socket. Double PTY nesting, debugging nightmare.

Correct approach: use tmux native commands (`list-sessions`, `send-keys`, `capture-pane`) directly + `tmux -L` custom socket. `node-pty` is unnecessary for session management. It only makes sense for raw PTY data streaming, but tmux `capture-pane` already provides output capture.

PLAN's 250-line `tmux-transport.js` estimate conflates two separate concerns (session management vs output capture) without addressing the PTY nesting issue.

## Non-Blocking Findings

**NOTE-1: Relay multi-client is simpler than PLAN claims, but has hidden cost**

Reading `relay/relay.js`: `session.clients` is already a `Set`. Mac → all clients broadcast is already implemented (lines 164-169). The only change needed is deleting the "disconnect old client" loop at lines 133-148 (~10 lines). PLAN's estimate is accurate.

However: tmux output is high-frequency (every keystroke triggers output). Relay broadcasts to N clients with fire-and-forget `client.send(msg)` — no backpressure. If one client is slow (e.g. phone on bad network), it blocks the broadcast loop. PLAN mentions "per client independent backpressure" but relay code has none.

**NOTE-2: PLAN work estimate is low**

PLAN estimates 750 new lines + 210 changes. Does not account for:
- Architecture design work for tmux single-attach limitation (BLOCK-2)
- node-pty removal/replacement (BLOCK-3)
- ANSI rendering edge cases on iOS (PLAN dismisses as "v1 strip all, v2 later" but stripping all color makes terminal output hard to read)
- Testing multi-client relay under load

Realistic estimate: 2x the stated numbers minimum.

**NOTE-3: ANSI handling strategy needs rethinking**

PLAN v1 uses `strip-ansi` (pure text, no colors). Terminal output without colors is significantly harder to parse — error messages, git diff output, syntax highlighting all lose meaning. Consider starting with basic ANSI color support via `node-ansiparser` from v1, or the iOS terminal will be nearly unusable for real work.

**NOTE-4: `AGENTS.md` listed as read-only in pack but untracked in git**

No conflict for this review, but the pack should only reference tracked files.

## Boundary Check

- No out-of-scope files changed: yes (only LICENSE in commit)
- No forbidden external actions: yes
- Validation evidence reviewed: N/A (no feature code to validate)

## Plan Assessment Summary

| Dimension | Score | Notes |
|-----------|-------|-------|
| Requirement understanding | Accurate | Scenarios correctly capture user needs |
| Architecture direction | Correct | Transport abstraction + relay multi-client is right |
| Technical details | **Has hard blockers** | node-pty nesting + tmux single-attach not resolved |
| Work estimate | **Low** | Missing design work + ANSI rendering complexity |
| Phase ordering | Reasonable | Phase 1-5 sequence is logical |

**Recommendation:** Resolve BLOCK-2 and BLOCK-3 before starting Phase 2. The relay change (Phase 1) is safe to proceed independently.
