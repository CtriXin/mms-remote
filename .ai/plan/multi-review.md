# Multi Review

This project uses the shared `multi-review` workflow.

## Short Invocation

```text
/multi-review <milestone> <commit>
/multi-review <milestone>
```

In reviewer sessions, `/multi-review <milestone>` means independent reviewer mode, not intake mode.

## Local Paths

```text
.ai/plan/review-packs/<milestone>.json
.ai/plan/review-packs/<milestone>.md
.ai/reviews/<reviewer>/<milestone>-review-YYYYMMDD.md
.ai/reviews/log/gate-<milestone>.json
.ai/reviews/log/index.jsonl
```

## Reviewer Rules

- Read the review pack first.
- First anchor to the repository root: `REPO_ROOT="$(git rev-parse --show-toplevel)" && cd "$REPO_ROOT"`.
- Review only the requested milestone.
- Do not modify code.
- Inspect only `read_only_files`, `changed_files`, and explicit evidence unless a blocker requires narrow expansion.
- Establish `REVIEWER_ID` before writing. Prefer explicit reviewer id, then `MMS_SESSION_PACKET_JSON` `model.primary`, then `MULTI_REVIEW_REVIEWER`, then generic `MMS_MODEL_NAME`.
- Never use wrapper/tool ids as `Reviewer` unless one is explicitly expected as a reviewer id or alias: `claude-code`, `codex`, `gemini-cli`, `mms`, `cli`, `unknown`, `default`, `reviewer`, `agent`, `local`.
- `CLI:` records the wrapper/tool; `Reviewer:` records the model identity. These must not be conflated.
- Do not normalize, prettify, title-case, lowercase, or otherwise rewrite `REVIEWER_ID`.
- If `REVIEWER_ID` is ambiguous, stop and ask; do not write a review file.
- Write exactly one review file under `.ai/reviews/<REVIEWER_ID>/`.
- The `Reviewer:` header must match `.ai/reviews/<REVIEWER_ID>/` exactly and case-sensitively; `CLI:` is only the wrapper/tool name.
- Fixed reviewer rosters should use exact MMS model ids. Intake may count explicit `identity.aliases` or an opt-in unique case-insensitive roster match, but it must not silently rewrite the review file identity.
- If the pack has `review_focus.assignments`, resolve your focus lane from your exact `Reviewer:` id and review that focus. Use `review_focus.default_lane` only when no assignment matches. Same `/multi-review <milestone> <commit>` invocation is used for every reviewer; do not ask the host for a separate pasted prompt.
- Before finishing, verify the output path is under `$REPO_ROOT/.ai/reviews/`, not under a subdirectory such as `tests/.ai/reviews/`.
- Use `PASS`, `PASS_WITH_NOTES`, or `BLOCKED`.
- Do not declare the gate clear or complete; only host/intake mode can do that.
- If `gate-<milestone>.json` is already clear, treat it as context only. Still write your review file or state that your reviewer id already has one.

## Host Rules

- Use quorum instead of waiting for every reviewer.
- Any valid `BLOCKED` verdict blocks the gate.
- Record slow or skipped reviewers after quorum.
- Late reviews may be appended later; only reopen the gate for real blockers.
- Capture repeated reviewer friction in this file or propose a shared `multi-review` skill update.
