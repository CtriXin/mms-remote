继续 `/Users/xin/auto-skills/CtriXin-repo/mms-remote`。

## 先读

1. `AGENTS.md`
2. `.ai/plan/current.md`
3. `.ai/plan/progress/terminal-pane-session-handoff-20260517.md`
4. `.ai/plan/progress/terminal-tui-replay-todo-20260517.md`
5. `.ai/plan/progress/upstream-remodex-watchlist-20260518.md`
6. `.ai/plan/v2-roadmap.md`
7. `git log -n 12 --oneline`
8. `git status --short`
9. `git worktree list`

## 当前稳定点

- branch: `main`
- docs baseline before this refresh: `2874a88 docs: record terminal final handoff`
- app code baseline: `39d623d merge: adopt localization polish`
- iOS version in repo: `1.7.111 build 149`
- Bridge package version: `mms-remote-bridge/package.json` = `1.7.64`（下一次 Bridge release/version 要显式决定是否同步）
- installed: `song的iPhone`; `iPhone 15 ProX雨` 当时 unavailable。
- backup branch before final FF: `backup/main-before-localization-final-20260518`
- integration branch/worktree still exists: `merge/swiftterm-ghost-into-pane-sheet`，不要删除或 reset。

## Terminal / SwiftTerm 决策

- 保留 bottom `Sessions` drawer，不恢复旧 left sidebar Terminal 实验。
- 保留 `144fc1b` 后稳定线；不要恢复 reconnect/glass 大改导致的 flicker、resize error、无法滚动回归。
- `9d7bc77` 是关键：手机 SwiftTerm active stream 不再调用共享 `terminal/resize` 去压 Mac tmux window。
- Terminal 显示类问题优先只改 iOS renderer/client；不要轻易改共享 tmux window 或 Bridge resize 协议。
- TUI replay/resize 乱码仍单开专项：见 `.ai/plan/progress/terminal-tui-replay-todo-20260517.md`。

## Upstream Remodex / OSS 结论

- Upstream Remodex checked at `origin/main` = `603dfc5`，license = Apache-2.0。
- 保留 Apache-2.0 `LICENSE` 和 `NOTICE` attribution；不要暗示 upstream endorsement。
- Upstream direct SSH/GhosttyKit/Citadel 不符合当前 Mac-local Bridge/tmux/SwiftTerm 架构，不整条引入。
- Remodex contribution policy 不适合现在准备大 PR；如未来贡献，先 issue/RFC，再 tiny focused patch。
- 未来只借鉴：iPad support、foreground WebSocket keepalive、composer draft persistence、My Macs、relay subpath、timeline/markdown performance、Terminal UX 小点。

## Dirty / cache policy

- `.codegraph/`、`.omc/`、`mms-remote-bridge/.omc/`、`tmp/` 是本地工具/cache/log，不提交。
- 不要删除并行 worktree 或 cache 目录，除非用户明确同意。
- 不要 revert 用户或其他 agent 的未提交改动；先 `git status --short` 分类。

## Commit / branch / version 规则

- 每个小功能/修复一个清晰 commit；不要长期堆 dirty main。
- iOS code change 必须 bump `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`。
- 可安装 build 要有独立清晰 commit；不要只安装不 commit。
- 不要跑 Xcode tests，除非用户明确说跑。

## 常用验证

Node/Bridge：

```bash
HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test --prefix mms-remote-bridge
```

iOS generic build：

```bash
xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData-next CODE_SIGNING_ALLOWED=NO build
```

iOS signed device build/install：

```bash
HOME=/Users/xin xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'id=00008150-0008781C36D9401C' -derivedDataPath .build/DerivedData-device build
xcrun devicectl device install app --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 .build/DerivedData-device/Build/Products/Debug-iphoneos/CodexMobile.app
```

## 回复风格

- 中文简体；Technical terms 保持 English。
- 结论先行，短回复；先行动，少问。
