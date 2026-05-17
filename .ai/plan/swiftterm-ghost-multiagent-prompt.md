# SwiftTerm Ghost Multiagent Investigation Prompt

Continue `/Users/xin/auto-skills/CtriXin-repo/mms-remote`.

Read first:
1. `AGENTS.md`
2. `.ai/plan/current.md`
3. `Docs/swiftterm_ghost_analysis.md`
4. `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalCanvasView.swift`
5. `CodexMobile/CodexMobile/Views/Terminal/SwiftTerminalHubView.swift`
6. `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/iOS/iOSTerminalView.swift`
7. `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/Apple/AppleTerminalView.swift`
8. `.build/DerivedData-device/SourcePackages/checkouts/SwiftTerm/Sources/SwiftTerm/iOS/iOSCaretView.swift`
9. `mms-remote-bridge/src/tmux-control-adapter.js`
10. `mms-remote-bridge/src/terminal-stream-hub.js`

Current stable device point:
- iOS `1.7.53 build 91`
- Installed and launched on `song的iPhone`
- User says blank startup / `cd` display /乱码 fixed
- Remaining bug: SwiftTerm visual ghost/影子 after input; switching/refreshing clears it
- This is visual only: buffer content appears correct

Do not repeat failed paths:
- Do not disable SwiftTerm
- Do not use replay/full-screen refresh as final fix
- Do not retry RunLoop/default-mode stream drain from `1.7.49/87`
- Do not reintroduce hidden input proxy + mobile cursor quarantine as the main fix
- Do not set stream start to `replay: false` only; that caused blank startup
- Do not upgrade SwiftTerm to latest `602be53` unless Metal Toolchain issue is solved; generic build failed due missing Metal Toolchain

Known current implementation:
- Native SwiftTerm input/caret path restored in `SwiftTerminalCanvasView.swift`
- Font assignment now happens only when changed
- SwiftTerm stream starts with `replay: true, replayViewportOnly: true`
- Post-input replay remains disabled
- Bridge normalizes terminal output once: bare LF -> CRLF; duplicate CR collapsed

Task:
1. Identify most likely root cause of ghost using code evidence.
2. Say whether root is SwiftTerm renderer/compositor/caret layer, Bridge bytes/order, or iOS host integration.
3. Propose one minimal diagnostic patch and one minimal real patch.
4. Explain how to validate without Xcode tests.
5. Keep answer short, with file/line refs.

Validation commands available:
```bash
cd /Users/xin/auto-skills/CtriXin-repo/mms-remote
HOME=/Users/xin CODEX_HOME=/Users/xin/.codex npm test --prefix mms-remote-bridge
xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'generic/platform=iOS' -derivedDataPath .build/DerivedData-ghost-next CODE_SIGNING_ALLOWED=NO build
HOME=/Users/xin xcodebuild -project CodexMobile/CodexMobile.xcodeproj -scheme CodexMobile -configuration Debug -destination 'id=00008150-0008781C36D9401C' -derivedDataPath .build/DerivedData-device build
xcrun devicectl device install app --device 009568BB-3B27-5C91-A94D-34B683F6BCD5 .build/DerivedData-device/Build/Products/Debug-iphoneos/CodexMobile.app
```

Rules:
- Chinese simplified response, technical terms English
- iOS code change must bump version/build
- Install only to `song的iPhone`
- No Xcode tests unless user explicitly asks
- Do not expose private relay endpoints
- Do not revert unrelated dirty files
