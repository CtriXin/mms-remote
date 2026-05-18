# Terminal Pane / SwiftTerm Ghost Final Handoff

Updated: 2026-05-18T01:58:00-04:00
Owner: codex
Status: merged to `main`, installed on `song的iPhone`, ready for user smoke validation.

## Final State

- `main` HEAD: `39d623db9c2e6854a15d40666b9dce8d3f42d077`
- `merge/swiftterm-ghost-into-pane-sheet` HEAD: `39d623db9c2e6854a15d40666b9dce8d3f42d077`
- iOS version: `1.7.111 (149)`
- Main merge method: clean fast-forward from integration branch; no code conflicts.
- Backup branch before final FF: `backup/main-before-localization-final-20260518`
- Installed device: `song的iPhone` via `scripts/ios-install-device.sh --device 00008150-0008781C36D9401C --no-launch`
- Unavailable device: `iPhone 15 ProX雨` stayed `unavailable`, not installed.

## Branch / Worktree Notes

- Main worktree: `/Users/xin/auto-skills/CtriXin-repo/mms-remote`
- Integration worktree: `/Users/xin/auto-skills/CtriXin-repo/mms-remote-merge-swiftterm`
- Localization worktree: `/Users/xin/auto-skills/CtriXin-repo/mms-remote/.claude/worktrees/localization-fix`
- Current `main` still has pre-existing dirty/untracked local planning and tool files. They were intentionally not touched by the merge/doc pass:
  - tracked `.ai/plan/*.md` edits outside this progress note
  - untracked `.codegraph/`, `.omc/`, `mms-remote-bridge/.omc/`, `tmp/`
- This handoff pair (`terminal-pane-session-handoff-20260517.md` / `.toon`) and the TUI replay TODO update are the only progress docs meant to be recorded now.

## What Was Merged

This final line combines:

1. Terminal Pane Sheet baseline from `feat/terminal-pane-sheet-from-1.7.65`.
2. SwiftTerm ghost/影子 fixes from `worktree/swiftterm-ghost-9000`.
3. Keyboard shortcut bar, Control/Option latch, direction pad, paste/font preference fixes.
4. Terminal stability rollback after reconnect/glass experiments.
5. Shared tmux resize fix so iPhone no longer shrinks the Mac terminal window.
6. Full app localization polish from `worktree-localization-fix`.

## Critical Decisions

- Keep the bottom `Sessions` drawer path; do not restore the old left-sidebar Terminal experiment.
- Keep the stable Terminal state after `144fc1b`, not the later reconnect/glass experiments that caused flicker/resize/scroll regressions.
- iPhone SwiftTerm must not call global `terminal/resize` while streaming an existing shared tmux pane. The key fix is `9d7bc77`.
- Terminal display-only fixes should stay on iOS renderer/client side unless a separate bridge/tmux protocol change is deliberately planned.
- Do not continue patching TUI replay/resize by trial-and-error in this merge line; keep it as a separate专项.

## Build / Commit History To Remember

| Version / Build | Commit | Meaning |
| --- | --- | --- |
| `1.7.91 (129)` | `634473c` | Merge SwiftTerm ghost fixes into pane-sheet integration. |
| `1.7.92 (130)` | `8ae3d95` | Streamline Terminal keyboard chrome. |
| `1.7.93 (131)` | `00aba1f` | Stabilize terminal keybar controls. |
| `1.7.93 (131)` | `67ef7ff` | Update logo assets. |
| `1.7.94 (132)` | `674e1d1` | Refine Terminal shortcut preferences. |
| `1.7.95 (133)` | `0da6244` | Preserve Terminal paste and chat font preferences. |
| `1.7.96 (134)` | `75dd9bd` | Steady fixed key controls; reduce SwiftUI phantom animation. |
| `1.7.97 (135)` | `178262b` | Try viewport replay for terminal agents/TUI. |
| `1.7.98 (136)` | `770cb29` | Try sizing terminal before streaming; later confirmed problematic. |
| `1.7.99 (137)` | `9251cc2` | Revert previous stream-start resize attempt. |
| `1.7.99 (137)` | `e9788e1` | Document Terminal TUI replay follow-up. |
| `1.7.100 (138)` | `bafe692` | Add Terminal reconnect recovery card attempt. |
| `1.7.101 (139)` | `865d78e` | Align Terminal chrome with chat glass. |
| `1.7.102 (140)` | `0b76c5e` | Restore Terminal glass contrast. |
| `1.7.103 (141)` | `96d6c8b` | Move Terminal top inset into canvas chrome. |
| `1.7.104 (142)` | `6111d1c` | Keep Terminal glass over top spacer. |
| `1.7.105 (143)` | `694c6f2` | Tighten Terminal top spacer. |
| `1.7.106 (144)` | `4cf86aa` | Stabilize Terminal top glass spacer. |
| `1.7.107 (145)` | `144fc1b` | Revert to stable state before reconnect/glass changes. |
| `1.7.108 (146)` | `0be4e12` | Make Terminal resize nonblocking; still affected Mac tmux. |
| `1.7.109 (147)` | `ee1417b` | Improve light Terminal prompt contrast. |
| `1.7.110 (148)` | `9d7bc77` | Stop iPhone from resizing shared tmux windows. |
| `1.7.111 (149)` | `39d623d` | Merge localization polish into final main. |

Localization commits came from `worktree-localization-fix` and kept their original branch version `1.7.99 (137)` until final merge:

- `110bd28 fix(ios): localize all hardcoded UI strings`
- `5ce51e6 fix(ios): localize remaining hardcoded strings (round 2)`
- `10f694b fix(ios): localize RevenueCatPaywallView feature list and footer`
- `6965824 fix(ios): localize remaining SettingsView and usage strings`
- `6c25a5d fix(ios): finish localization polish`

## Merge Conflict History

The original ghost -> pane-sheet merge had two expected conflicts and was resolved before this final main FF:

1. `CodexMobile/CodexMobile.xcodeproj/project.pbxproj`
   - kept the newer app version/build line.
2. `mms-remote-bridge/src/terminal-stream-hub.js`
   - kept both replay window fields and trace field:

```js
replayViewportOnly: params.replayViewportOnly === true,
replayStart: replayStart(params),
replayEnd: replayEnd(params),
replayMaxBuffer: replayMaxBuffer(params),
lastOutputTraceKey: "",
```

The final integration -> `main` merge on 2026-05-18 was a fast-forward and had no conflicts.

## Validation Already Done

- `git diff --check` on integration before final merge: passed.
- `git diff --check` on main after final merge: passed.
- Localization duplicate-key scan after final merge: passed (`>2` duplicate count empty).
- Generic iOS Simulator build after localization merge: passed.
- Physical iOS build/install to `song的iPhone`: passed.

## Device Smoke Checklist

Still useful for the user to confirm on the installed `1.7.111 (149)` build:

- Terminal bottom `Sessions` opens Terminal drawer.
- Codex bottom `Sessions` opens Chat session drawer.
- Terminal drawer search/new/refresh/settings work.
- Terminal settings returns correctly and shows Terminal + Bridge Version + Connection.
- Keyboard show/hide works and does not refocus unexpectedly.
- Shortcut bar, Control/Option latch, and direction pad work.
- SwiftTerm ghost/影子 remains gone.
- iPhone no longer shrinks Mac tmux window size.
- Mac terminal scrolling/background returns to normal after Mac redraw/new output.
- Localization appears correctly in Chinese and English.

## Known Follow-ups

- Terminal TUI replay/resize 乱码 remains a separate专项; see `.ai/plan/progress/terminal-tui-replay-todo-20260517.md`.
- Old scrollback generated while tmux was 55 columns will not reflow automatically; new output/redraw should be normal.
- `iPhone 15 ProX雨` should be installed later only when it becomes available.
- Do not run Xcode tests unless explicitly requested.
