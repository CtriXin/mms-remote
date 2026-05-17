# P184 MMSChat P8C Codex Rollout Provider Result

- Verdict: `PASS_CODEX_ROLLOUT_PROVIDER_READY`
- Progress: expanded unified local-agent Sessions `98% -> 100%`
- Worktree: `/Users/xin/auto-skills/CtriXin-repo/mms-remote-p184-mmschat-p8c-codex-rollout-provider`
- Branch: `p184/mmschat-p8c-codex-rollout-provider`
- Base checkpoint: `09282b437b3c5502ed5a26fe675cf87406f351e2`

## Result

MMSChat now includes read-only Codex CLI/TUI rollout sessions beside native Claude sessions. The new helper scans `CODEX_HOME/sessions/**/rollout-*.jsonl` and falls back to `~/.codex/sessions` only when no explicit Codex home is configured.

`mmschat/list` registers Codex rollout sessions with `agent=codex`, `provider=codex`, and `metadata.source=codex-rollout`. List payloads expose only capped metadata such as counts, timestamps, file byte size, and hashes; raw transcript text and command output stay out of list responses.

`mmschat/detail` re-reads Codex rollout files instead of using the derived transcript cache, so active/running rollout files can surface the latest detail state. Detail normalizes user, assistant, reasoning, tool call, and command-output records while ignoring schema drift safely.

The protocol registry now permits `agent=codex`, iOS decodes `codex-rollout` transcript sources, and bridge/iOS marketing version moved `1.7.57 -> 1.7.58`.

## Validation

- PASS: `node --check` for changed bridge source files.
- PASS: `node --test test/mmschat-codex-rollout.test.js test/mmschat-hub.test.js test/mmschat-demo-fixtures.test.js test/mms-metadata-hub.test.js test/bridge.test.js`.
- PASS: `xcodebuild -quiet -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/p184-p8c-derived-data CODE_SIGNING_ALLOWED=NO build`.
- PASS: `python3 -m json.tool .ai/plan/p184-mmschat-p8c-codex-rollout-provider-result.json`.
- PASS: `git diff --check`.

## HumanGate

No dependency add, deploy, push, global config mutation, destructive cleanup, native Claude history deletion, phone install, or live provider/model call was performed.
