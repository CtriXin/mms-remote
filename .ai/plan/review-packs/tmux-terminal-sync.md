# tmux-terminal-sync Review Pack - Tmux Terminal Sync & Multi-Backend

## Short Invocation

```text
/multi-review tmux-terminal-sync 6e1f7a05af134e510e9a2fa811a978e5eab79e50
```

## Summary

Add tmux transport to bridge, enabling phone to view/control all Mac terminal windows bidirectionally. Relay multi-client support. iOS terminal renderer. Preserve existing Codex mode.

## Scope

- Milestone: `tmux-terminal-sync`
- Commit: `6e1f7a05af134e510e9a2fa811a978e5eab79e50`
- Status: `ready_for_review`
- Gate output: `.ai/reviews/log/gate-tmux-terminal-sync.json`

## Read Only Files

- `AGENTS.md`

## Changed Files

- `LICENSE`

## Validation

- not recorded

## Non-Goals

- not recorded

## Review Questions

1. Does this change satisfy the declared scope without opening non-goal boundaries?

## Repository Root Preflight

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
test -f ".ai/plan/review-packs/tmux-terminal-sync.json"
```

Review output is invalid if it is written under a subdirectory such as `tests/.ai/reviews/`.

## Reviewer Identity

- `Reviewer:` must match `.ai/reviews/<reviewer>/` exactly and case-sensitively.
- Prefer exact MMS model ids in `roles.reviewers`; use `identity.aliases` for shorthand/display variants.
- Do not prettify or display-case reviewer ids in reviewer mode.
- `CLI:` is only the wrapper/tool name.
- Examples: `Reviewer: K2.6` is valid for `.ai/reviews/K2.6/` when `K2.6` is the MMS model id. A `k2.6` roster may count `K2.6` only through `identity.aliases` or an explicit unique case-insensitive roster policy.

## Expected Verdict Format

```markdown
# tmux-terminal-sync Review - Tmux Terminal Sync & Multi-Backend

- Date:
- Reviewer:
- CLI:
- Started:
- Completed:
- Duration:

## Overall Verdict
PASS / PASS_WITH_NOTES / BLOCKED

## Blocking Findings
- none, or BUG-1 / TEST-1 with file refs

## Non-Blocking Findings
- optional

## Boundary Check
- No out-of-scope files changed: yes/no
- No forbidden external actions: yes/no
- Validation evidence reviewed: yes/no
```
