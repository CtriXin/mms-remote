# P8K Codex Rollout Phone Polish Result

**Status: PASS** - Trace: `trc-20260516T082907Z-f43b858883`

## Commit Lineage

- Original base commit remains `b4d57d2d96d6927e69f5cb1bd3d770a0ae3a6fdd`
- `255899d` - initial cleanup commit: `fix(mmschat): clean codex rollout replay`
- `6f2fa02` - first release-gate repair commit: `fix(mmschat): filter codex rollout context roles`
- Pending follow-up commit - second release-gate repair: `fix(mmschat): narrow codex bootstrap filters`

## Files Changed

- `mms-remote-bridge/src/mmschat-codex-rollout.js`
- `mms-remote-bridge/test/mmschat-codex-rollout.test.js`
- `.ai/plan/p184-mmschat-p8k-codex-rollout-phone-polish-result.json`
- `.ai/plan/p184-mmschat-p8k-codex-rollout-phone-polish-result.md`

No Swift files changed. Existing read-only replay/localization in the iOS app continues to document historical replay behavior.

## Screenshot Findings Addressed (5/5)

| # | Finding | Fix |
|---|---------|-----|
| 1 | Duplicate-looking titles | Real prompt titles with rollout id fallback |
| 2 | Bootstrap/context records leaked | Hidden from list, detail, count, and title |
| 3 | Empty Thinking placeholders | Suppressed for empty/whitespace-only content |
| 4 | Read-only replay on iOS | Preserved; no Swift change needed |
| 5 | Session_meta-only empty rollouts | Excluded from list and count |

## Release-Gate Repairs

### First repair - committed in `6f2fa02`

- System/developer `response_item` role messages are filtered before they enter chat, counts, or titles.
- Existing regression coverage verifies role filtering, title fallback behavior, and the earlier false-positive guard.

### Second repair - pending commit

- Bootstrap filters in `mmschat-codex-rollout.js` are narrowed to explicit injected AGENTS.md, `<INSTRUCTIONS>`, and MCP bootstrap shapes.
- Legitimate user prompts mentioning MCP, `<INSTRUCTIONS>`, or AGENTS remain visible instead of being discarded as bootstrap context.
- Test coverage adds negative regression assertions for legitimate MCP, `<INSTRUCTIONS>`, and AGENTS prompts.

## Validation

```text
cd mms-remote-bridge && node --test test/mmschat-codex-rollout.test.js
  PASS: 18 tests, 18 passed, 0 failed

cd mms-remote-bridge && node --test test/mmschat-*.test.js
  PASS: 52 tests, 52 passed, 0 failed

git diff --check
  PASS: no output - no whitespace errors

xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -derivedDataPath .build/p8k-codex-rollout-phone-polish-derived \
  CODE_SIGNING_ALLOWED=NO build
  PASS: BUILD SUCCEEDED
```

## Hard Boundaries Confirmed

- Main worktree untouched
- No phone install
- No push or deploy
- No global config, keychain, or dependency changes
- No bridge start/stop/reconfigure
- No Swift changes

## Risks

- Phone reinstall and on-device verification were not performed.
- Real live send, resume, open-visible, and kill flows were not exercised.
- Result artifacts record the second repair as pending because they are part of the commit payload; the final commit hash must be reported separately after commit.
- HumanGate is still recommended before any live deployment or device validation.

## Next Step

HumanGate for version stamp and/or install candidate if desired. No push without explicit instruction.

Branch: `p184/mmschat-p8k-codex-rollout-phone-polish`
Base: `b4d57d2d96d6927e69f5cb1bd3d770a0ae3a6fdd`
Head before follow-up commit: `6f2fa02d4fc1041c3bbc1e7396b8d206f1b3ae55`
Updated: `2026-05-19T02:35:57Z`
