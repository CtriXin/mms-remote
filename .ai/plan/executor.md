# Executor Rules

- Use `/executor <task-id> <commit>` in executor sessions.
- Read `.ai/exec/packs/<task-id>.json` first.
- Establish `EXECUTOR_ID` from explicit `executor=<id>`, `MMS_SESSION_PACKET_JSON -> model.primary`, `EXECUTOR_ID`, or `MMS_MODEL_NAME`.
- Wrapper ids belong in `CLI:`, not `Executor:`.
- Modify only pack `writable_files` plus the declared result artifact.
- Include confidence, complexity, completion, debug depth, evidence quality, risk, and status scores.
- Include scope compliance, validation evidence, findings/loophole review, residual risk, and blast radius.
- Use PASS only when criteria are met and blocking findings are absent; otherwise use PARTIAL or BLOCKED.
- Host intake decides whether the task is complete.
