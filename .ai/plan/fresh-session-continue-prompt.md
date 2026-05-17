继续 `/Users/xin/auto-skills/CtriXin-repo/mms-remote`。

## 先读

1. `AGENTS.md`
2. `.ai/plan/current.md`
3. `.ai/plan/handoff.md`
4. `.ai/plan/packet.json`
5. `.ai/plan/progress/swiftterm-ghost-multiagent.md`
6. `Docs/swiftterm_ghost_analysis.md`
7. `.ai/plan/v2-roadmap.md`
8. `git log -n 8 --oneline`
9. `git status --short`
10. `git worktree list`

## 当前稳定点

- branch: `main`
- latest clean commit: `f676d48 feat(ios): add sidebar multi-select actions`
- installed iOS: `1.7.53 build 91`
- device: `song的iPhone`
- current state: app usable；blank startup / `cd` display /乱码 已修；SwiftTerm visual ghost/影子仍存在，已记录，别继续盲卡。
- SwiftTerm ghost docs:
  - `.ai/plan/progress/swiftterm-ghost-multiagent.md`
  - `.ai/plan/swiftterm-ghost-external-agent-prompt.md`
  - `Docs/swiftterm_ghost_analysis.md`

## 重要：先处理 dirty/main 纪律

现在 main 很脏，最近很多改动没 commit。用户明确要求之后小步 commit，不要长期堆 dirty main。

新 session 第一件事：

```bash
git status --short
git diff --stat
git log -n 8 --oneline
```

然后分组处理：

- docs/handoff 一组；可单独 commit。
- Bridge/Node 一组；需跑 `HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test --prefix mms-remote-bridge`。
- iOS UI/code 一组；必须 bump version/build，build 过，再安装到 `song的iPhone`。
- 不要 revert unrelated dirty files。
- 不要把多个无关任务揉成一个大 commit。

## Commit / branch / version 规则（强制）

- 每个小功能/修复一个小分支或小 commit；验证通过就 commit。
- 可安装 build 要有独立小分支/小 commit；不要只改完安装不 commit。
- version/build bump 单独成清晰 commit；需要时用中间 version branch，再合并回大分支/main。
- `x.y.z` 对应变更范围：小修 patch bump `z`；中等功能 bump `y`；大版本 bump `x`。
- iOS code change 必须 bump `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`。
- 同步 package version：至少检查 `mms-remote-bridge/package.json` 的 `version`，要和全局 release 版本一致；如果其他 `package.json` 有 `version` 也同步。不要给无版本 package 乱加 version，除非明确决定项目规范。
- 当前发现：`CodexMobile` 是 `1.7.53/91`，但 `mms-remote-bridge/package.json` 仍是 `1.5.0`；下一次 release/version 分支要修正。

## 下一步准备合并样式 worktree

目标 worktree / branch：

- worktree: `.claude/worktrees/terminal-style-unify`
- branch: `feat/terminal-style-unify`
- 当前 branch 指向和 `main` 同一个 commit `f676d48`
- 真实样式改动还没 commit，存在 worktree dirty files：
  - `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`
  - `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalShortcutViews.swift`

不要直接 `git merge feat/terminal-style-unify`，因为 branch 没有新 commit，merge 不会带入 dirty worktree 改动。

正确流程：

```bash
git -C .claude/worktrees/terminal-style-unify status --short
git -C .claude/worktrees/terminal-style-unify diff --stat
git -C .claude/worktrees/terminal-style-unify diff -- CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalShortcutViews.swift
```

然后选择安全路径：

1. 在 style worktree 内验证/整理，commit 到 `feat/terminal-style-unify`，再回 main merge/cherry-pick。
2. 如果 main 同文件已有 dirty 改动，先比较两边 diff，手工整合，避免覆盖。
3. 合并后如涉及 iOS UI/code，bump 到下一版本/build，建议从 `1.7.53/91` 到 `1.7.54/92`，同时同步 `mms-remote-bridge/package.json` 到 `1.7.54`。

## SwiftTerm ghost 状态

不要把新 session 卡死在 ghost 上。

- 当前 ghost 已 multiagent 调研并落档。
- 若用户要求继续修 ghost，走证据路径：SwiftTerm source-level visibleRect/row clear + Bridge/iOS seq/hash trace。
- 禁止重试：disable SwiftTerm、replay/full-refresh 当最终修复、`1.7.49/87` RunLoop/default-mode drain、hidden input proxy/caret quarantine 主方案、startup `replay:false` live-only、无 Metal Toolchain 下直接升级 latest SwiftTerm。

## Relay / public 规则

- 保留用户本地/双服务器 relay 能力。
- 不要把用户 private relay endpoints 写进公开 docs/code/log。
- 公开版/App Review 不能默认让别人使用用户公网 relay；需要用户自配或明确公开服务策略。

## 验证规则

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
xcrun devicectl device process launch --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 com.mms.remote
```

不要跑 Xcode tests，除非用户明确说跑。

## 回复风格

- 中文简体。
- Technical terms 保持 English。
- 结论先行，短回复。
- 先行动，少问；风险大才问。
