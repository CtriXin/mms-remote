# MMSChat P8C Codex Rollout Provider Progress

- Status: `PASS_CODEX_ROLLOUT_PROVIDER_READY`
- Timestamp: `2026-05-17T08:06:37Z`
- Owner: `sisyphus-omo-p-agent`
- Scope: P184 P8C read-only Codex rollout provider for unified local-agent Sessions.

## Completed

- Added `mmschat-codex-rollout.js` to discover Codex CLI/TUI rollout JSONL files from local Codex sessions roots.
- Wired `mmschat/list` to include Codex rollout sessions as metadata-only rows with `provider=codex` and `source=codex-rollout`.
- Wired `mmschat/detail` to normalize Codex rollout JSONL into unified transcript messages without terminal/tmux reverse parsing.
- Added focused helper and hub integration tests for discovery, schema drift, list redaction, and detail normalization.
- Bumped bridge/iOS marketing version to `1.7.58`.

## Evidence

- Result JSON: `.ai/plan/p184-mmschat-p8c-codex-rollout-provider-result.json`
- Result MD: `.ai/plan/p184-mmschat-p8c-codex-rollout-provider-result.md`
- Validation: required Node syntax/tests passed; iOS simulator build passed; JSON artifact validation and `git diff --check` passed.

## Remaining Gates

- Commit if final checks pass, per P8C prompt.
