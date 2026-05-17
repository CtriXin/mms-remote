// FILE: SwiftTerminalHubView.swift
// Purpose: Experimental Swift terminal tab isolated from the existing CLI Terminal tab.
// Layer: View
// Exports: SwiftTerminalHubView
// Depends on: SwiftUI, UIKit, CodexService, TerminalModels, SwiftTerminalCanvasView

import SwiftUI
import UIKit

struct SwiftTerminalHubView: View {
    @Environment(CodexService.self) private var codex
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("swiftTerminal.fontSize") private var fontSize = 12.0
    @AppStorage("swiftTerminal.bracketedPaste") private var bracketedPaste = true
    @AppStorage("swiftTerminal.rendererMode") private var rendererModeRaw = SwiftTerminalRendererMode.stable.rawValue
    @AppStorage("swiftTerminal.shortcutProfile") private var shortcutProfileRaw = SwiftTerminalShortcutProfile.agent.rawValue
    @AppStorage("swiftTerminal.customShortcutsJSON") private var customShortcutsJSON = SwiftTerminalShortcut.defaultCustomJSON
    @AppStorage("swiftTerminal.pinnedShortcutIds") private var pinnedShortcutIdsRaw = SwiftTerminalShortcut.defaultPinnedIds
    @AppStorage("swiftTerminal.stableDefaultRevision") private var stableDefaultRevision = 0
    @AppStorage("swiftTerminal.chordMode") private var chordModeEnabled = false
    @AppStorage(TerminalFontFamily.storageKey) private var terminalFontFamilyRaw = TerminalFontFamily.defaultStoredRawValue
    @AppStorage("terminal.darkCanvas") private var useDarkTerminalCanvas = true
    @AppStorage(TerminalVisibleAppPreference.storageKey) private var terminalVisibleAppRaw = TerminalVisibleAppPreference.defaultStoredRawValue
    @AppStorage("terminal.openVisibleOnCreate") private var openVisibleTerminalOnCreate = false

    @State private var keyBarExpanded = false
    @State private var selectedChordModifiers = Set<SwiftTerminalChordModifier>()
    @State private var showsChordComposer = false
    @State private var selectedChordKeyPage = SwiftTerminalChordKeyPage.letters
    @State private var selectedChordPreviewKey: SwiftTerminalChordKey?
    @State private var chordPanelHeight: CGFloat = 280
    @State private var chordPanelDragStartHeight: CGFloat?
    @State private var selectedPaneTarget: String?
    @State private var streamId: String?
    @State private var paneTitle = "Terminal"
    @State private var statusLine = "idle"
    @State private var isRefreshing = false
    @State private var isStartingStream = false
    @State private var isCreatingTerminal = false
    @State private var isSendingInput = false
    @State private var localErrorMessage: String?
    @State private var commandDraft = ""
    @State private var newTerminalCwd = "/"
    @State private var focusRequestID = 0
    @State private var copyRequestID = 0
    @State private var pasteRequestID = 0
    @State private var controlModifierRequestID = 0
    @State private var metaModifierRequestID = 0
    @State private var resetRequestID = 0
    @State private var pageUpRequestID = 0
    @State private var pageDownRequestID = 0
    @State private var blurRequestID = 0
    @State private var stableScrollTopRequestID = 0
    @State private var stableScrollBottomRequestID = 0
    @State private var latestSize: (cols: Int, rows: Int)?
    @State private var streamLifecycleToken = 0
    @State private var startStreamTask: Task<Void, Never>?
    @State private var shortcutEditorDraft = SwiftTerminalShortcut.defaultCustomJSON
    @State private var shortcutEditorError: String?
    @State private var showsShortcutEditor = false
    @State private var showsPinnedShortcutPicker = false
    @State private var isShowingTmuxCheatsheet = false
    @State private var pendingCloseRequest: SwiftTerminalCloseRequest?
    @State private var lastInputSignature = ""
    @State private var lastInputAt: TimeInterval = 0
    @State private var lastStreamReconnectSignature = ""
    @State private var swiftTerminalSubTab: TerminalSubTab = .terminal
    @FocusState private var isCommandFieldFocused: Bool
    private let stableFallbackRevision = 1
    private let emptyPinnedShortcutSentinel = "__empty__"
    private let chordPanelMinHeight: CGFloat = 244
    private let chordPanelMaxHeight: CGFloat = 420

    private var rendererMode: SwiftTerminalRendererMode {
        SwiftTerminalRendererMode(rawValue: rendererModeRaw) ?? .stable
    }

    private var shortcutProfile: SwiftTerminalShortcutProfile {
        SwiftTerminalShortcutProfile(rawValue: shortcutProfileRaw) ?? .agent
    }

    private var isSwiftTermRendererActive: Bool {
        rendererMode == .swiftTerm
    }

    private var theme: SwiftTerminalTheme {
        SwiftTerminalTheme.resolve(systemScheme: colorScheme, useDarkTerminalCanvas: useDarkTerminalCanvas)
    }

    private var terminalVisibleApp: TerminalVisibleAppPreference {
        TerminalVisibleAppPreference(rawValue: terminalVisibleAppRaw) ?? .auto
    }

    var body: some View {
        VStack(spacing: 0) {
            swiftTerminalSubTabPicker
                .padding(.horizontal, 16)
                .padding(.top, 4)

            if swiftTerminalSubTab == .terminal {
                if !codex.isConnected {
                    offlineBanner
                }
                header
                Divider().overlay(swiftTerminalBorder)
                terminalCanvas
                if showsChordComposer {
                    Divider().overlay(swiftTerminalBorder)
                    chordComposerPanel
                }
                keyBar
            } else {
                MMSChatListView()
            }
        }
        .background(theme.shellBackground)
        .navigationTitle(LocalizationManager.shared.localized("tab.terminal"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { createSwiftTerminal() } label: {
                    Image(systemName: "plus")
                }
                .disabled(!codex.isConnected || isCreatingTerminal)
                Button { refreshTerminals() } label: {
                    if isRefreshing { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
                .disabled(!codex.isConnected || isRefreshing)
            }
        }
        .task {
            enforceStableRendererDefaultIfNeeded()
            await primeTerminalOnEntry()
        }
        .onAppear {
            Task { await primeTerminalOnEntry() }
        }
        .task(id: stablePollKey) {
            await pollStableSnapshotIfNeeded()
        }
        .onDisappear {
            stopActiveStream(status: "hidden")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                stopActiveStream(status: "background")
            } else if phase == .active {
                if isSwiftTermRendererActive {
                    startStream()
                } else {
                    Task { await refreshStableSnapshotIfNeeded() }
                }
            }
        }
        .onChange(of: codex.isConnected) { _, isConnected in
            guard isConnected else {
                stopActiveStream(status: "offline", notifyBridge: false)
                return
            }
            Task {
                await refreshTerminalsAsync(preferUsefulDefault: true)
                await refreshStableSnapshotIfNeeded()
            }
        }
        .onChange(of: codex.terminalStreamRevision) { _, _ in
            handleActiveStreamRevision()
        }
        .onChange(of: selectedPaneTarget) { _, _ in
            paneTitle = selectedPane?.displayTitle ?? "Terminal"
            if isSwiftTermRendererActive {
                startStream()
            } else {
                stopActiveStream(status: "stable")
                Task { await refreshStableSnapshotIfNeeded() }
            }
        }
        .onChange(of: rendererModeRaw) { _, _ in
            if isSwiftTermRendererActive {
                startStream()
            } else {
                stopActiveStream(status: "stable")
                Task { await refreshStableSnapshotIfNeeded() }
            }
        }
        .alert(LocalizationManager.shared.localized("swift_terminal.error_title"), isPresented: errorIsPresented) {
            Button(LocalizationManager.shared.localized("common.ok"), role: .cancel) {
                localErrorMessage = nil
            }
        } message: {
            Text(localErrorMessage ?? "")
        }
        .confirmationDialog(
            closeDialogTitle,
            isPresented: closeDialogIsPresented,
            titleVisibility: .visible
        ) {
            if let pendingCloseRequest {
                Button(pendingCloseRequest.buttonTitle, role: .destructive) {
                    closeTerminal(pendingCloseRequest)
                }
            }
            Button(LocalizationManager.shared.localized("common.cancel"), role: .cancel) {
                pendingCloseRequest = nil
            }
        } message: {
            Text(closeDialogMessage)
        }
        .sheet(isPresented: $showsShortcutEditor) {
            shortcutEditorSheet
        }
        .sheet(isPresented: $showsPinnedShortcutPicker) {
            pinnedShortcutPickerSheet
        }
        .sheet(isPresented: $isShowingTmuxCheatsheet) {
            NavigationStack {
                TmuxCheatsheetView(sessionName: selectedPane?.sessionName)
                    .navigationTitle(LocalizationManager.shared.localized("terminal.cheatsheet.title"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(LocalizationManager.shared.localized("settings.close")) {
                                isShowingTmuxCheatsheet = false
                            }
                        }
                    }
            }
            .presentationDetents([.large])
        }
        .onChange(of: isCommandFieldFocused) { _, isFocused in
            if isFocused {
                keyBarExpanded = false
            }
        }
        .onChange(of: showsChordComposer) { _, isShowing in
            if isShowing {
                suppressKeyboardForChordComposer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyBarExpanded = false
        }
    }

    private var swiftTerminalSubTabPicker: some View {
        Picker("", selection: $swiftTerminalSubTab) {
            Text(LocalizationManager.shared.localized("mmschat.tab.terminal")).tag(TerminalSubTab.terminal)
            Text(LocalizationManager.shared.localized("mmschat.tab.sessions")).tag(TerminalSubTab.sessions)
        }
        .pickerStyle(.segmented)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text(paneTitleForHeader)
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text(statusText)
                    .font(AppFont.mono(.caption2))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 10)
            Menu {
                ForEach(displayedPanes) { pane in
                    Button {
                        selectedPaneTarget = pane.requestTarget
                    } label: {
                        Label(pane.displayTitle, systemImage: paneMatches(pane, target: selectedPaneTarget) ? "checkmark.circle.fill" : "terminal")
                    }
                }
                if let selectedPane {
                    Divider()
                    Button(role: .destructive) {
                        pendingCloseRequest = .pane(selectedPane)
                    } label: {
                        Label(LocalizationManager.shared.localized("terminal.context.close"), systemImage: "xmark.circle")
                    }
                    if !selectedPane.sessionName.isEmpty {
                        Button(role: .destructive) {
                            pendingCloseRequest = .session(selectedPane)
                        } label: {
                            Label(LocalizationManager.shared.localized("terminal.context.close_session"), systemImage: "rectangle.stack.badge.minus")
                        }
                    }
                }
            } label: {
                headerIcon("rectangle.stack")
            }
            .disabled(displayedPanes.isEmpty)

            Button {
                isShowingTmuxCheatsheet = true
            } label: {
                headerIcon("questionmark.circle")
            }
            .accessibilityLabel(LocalizationManager.shared.localized("terminal.accessibility.tmux_help"))

            Menu {
                Button {
                    rendererModeRaw = SwiftTerminalRendererMode.stable.rawValue
                } label: {
                    Label(SwiftTerminalRendererMode.stable.localizedTitle, systemImage: rendererMode == .stable ? "checkmark" : "doc.text")
                }
                Button {
                    rendererModeRaw = SwiftTerminalRendererMode.swiftTerm.rawValue
                } label: {
                    Label(SwiftTerminalRendererMode.swiftTerm.localizedTitle, systemImage: rendererMode == .swiftTerm ? "checkmark" : "bolt.horizontal")
                }
            } label: {
                headerIcon(isSwiftTermRendererActive ? "bolt.horizontal.circle" : "shield.lefthalf.filled")
            }

            Button {
                isSwiftTermRendererActive ? startStream() : refreshTerminals()
            } label: {
                if isStartingStream || isRefreshing {
                    ProgressView()
                } else {
                    Image(systemName: isSwiftTermRendererActive ? "bolt.horizontal.circle" : "arrow.clockwise")
                }
            }
            .frame(width: 38, height: 34)
            .background(theme.buttonBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(theme.buttonText)
            .disabled(!codex.isConnected || selectedPaneTarget == nil || isStartingStream || isRefreshing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(swiftTerminalPanel)
    }

    private var terminalCanvas: some View {
        Group {
            if displayedPanes.isEmpty && !codex.isLoadingTerminals {
                emptyState
            } else if isSwiftTermRendererActive {
                SwiftTerminalCanvasView(
                    paneTarget: selectedPaneTarget,
                    streamId: streamId,
                    messages: streamMessages,
                    fontSize: CGFloat(fontSize),
                    usesDarkTheme: theme.isDark,
                    focusRequestID: focusRequestID,
                    copyRequestID: copyRequestID,
                    pasteRequestID: pasteRequestID,
                    controlModifierRequestID: controlModifierRequestID,
                    metaModifierRequestID: metaModifierRequestID,
                    resetRequestID: resetRequestID,
                    pageUpRequestID: pageUpRequestID,
                    pageDownRequestID: pageDownRequestID,
                    blurRequestID: blurRequestID,
                    onSendData: sendTerminalData,
                    onResize: resizeTerminal,
                    onTitle: { paneTitle = $0 },
                    onStatus: { statusLine = $0 }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !showsChordComposer else {
                        suppressKeyboardForChordComposer()
                        return
                    }
                    keyBarExpanded = false
                    focusRequestID += 1
                }
            } else {
                stableSnapshotView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var stableSnapshotView: some View {
        GeometryReader { geometry in
            StableTerminalSnapshotTextView(
                attributedText: currentSnapshotAttributedText,
                fontSize: CGFloat(fontSize),
                backgroundColor: UIColor(theme.terminalSurface),
                scrollTopRequestID: stableScrollTopRequestID,
                scrollBottomRequestID: stableScrollBottomRequestID,
                resetKey: stableCanvasResetKey
            )
            .id(stableCanvasResetKey)
            .background(swiftTerminalBackground)
            .onAppear {
                resizeStableTerminalIfNeeded(size: geometry.size)
                Task { await refreshStableSnapshotIfNeeded() }
            }
            .onChange(of: geometry.size) { _, newSize in
                resizeStableTerminalIfNeeded(size: newSize)
            }
        }
    }

    private var ghosttyPromptStrip: some View {
        HStack(spacing: 0) {
            promptChip(promptUserText, color: Color(red: 0.12, green: 0.62, blue: 0.72))
            promptChip(promptPathText, color: Color(red: 0.12, green: 0.48, blue: 0.29))
            promptChip(promptBranchText, color: Color(red: 0.84, green: 0.52, blue: 0.18))
            promptChip(rendererMode.localizedShortTitle, color: Color(red: 0.29, green: 0.32, blue: 0.39))
            Spacer(minLength: 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var keyBar: some View {
        SwiftTerminalKeyBarView(
            isSwiftTermRendererActive: isSwiftTermRendererActive,
            keyBarExpanded: $keyBarExpanded,
            bracketedPaste: $bracketedPaste,
            fontSize: $fontSize,
            theme: theme,
            pinnedShortcuts: pinnedShortcuts,
            displayedActiveShortcuts: displayedActiveShortcuts,
            shortcutProfile: shortcutProfile,
            onFocusTerminalInput: { focusTerminalInput() },
            onHideTerminalKeyboard: { hideTerminalKeyboard() },
            onSelectPreviousPane: { selectAdjacentPane(offset: -1) },
            onSelectNextPane: { selectAdjacentPane(offset: 1) },
            onToggleKeyBarExpanded: { toggleKeyBarExpanded() },
            onControlModifier: { controlModifierRequestID += 1 },
            onMetaModifier: { metaModifierRequestID += 1 },
            onCopyTerminal: { copyTerminal() },
            onPasteClipboard: { pasteClipboard() },
            onOpenChordComposer: { openChordComposer() },
            onOpenPinnedShortcutPicker: { openPinnedShortcutPicker() },
            onSelectShortcutProfile: { profile in shortcutProfileRaw = profile.rawValue },
            onOpenShortcutEditor: { openShortcutEditor() },
            onSendShortcut: { shortcut in sendShortcut(shortcut) },
            stableInput: { stableCommandInputBar }
        )
    }

    private var chordComposerPanel: some View {
        SwiftTerminalChordComposerPanel(
            theme: theme,
            chordPanelHeight: $chordPanelHeight,
            chordPanelDragStartHeight: $chordPanelDragStartHeight,
            chordPanelMinHeight: chordPanelMinHeight,
            chordPanelMaxHeight: chordPanelMaxHeight,
            selectedChordModifiers: selectedChordModifiers,
            selectedChordKeyPage: $selectedChordKeyPage,
            chordPreviewGlyphText: chordPreviewGlyphText,
            chordPreviewValueText: chordPreviewValueText,
            onClose: { showsChordComposer = false },
            onToggleModifier: { modifier in toggleChordModifier(modifier) },
            onSendChordKey: { key in sendChordKey(key) },
            onAppearSuppressKeyboard: { suppressKeyboardForChordComposerRepeatedly() }
        )
    }

    private var stableCommandInputBar: some View {
        HStack(spacing: 8) {
            liveStatusBadge

            HStack(spacing: 8) {
                Text("$")
                    .font(AppFont.mono(.body))
                    .foregroundStyle(theme.terminalAccent)

                TextField(LocalizationManager.shared.localized("swift_terminal.command_placeholder"), text: $commandDraft, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppFont.mono(.body))
                    .lineLimit(1...3)
                    .focused($isCommandFieldFocused)
                    .foregroundStyle(theme.terminalText)
                    .tint(theme.terminalAccent)
                    .submitLabel(.send)
                    .onSubmit { sendCommandFromDraft() }
                    .disabled(keyBarExpanded || showsChordComposer)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.terminalInputBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(theme.terminalAccent.opacity(isCommandFieldFocused ? 0.44 : 0.16), lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard !keyBarExpanded && !showsChordComposer else {
                    hideTerminalKeyboard()
                    return
                }
                keyBarExpanded = false
                isCommandFieldFocused = true
            }

            Button { sendCommandFromDraft() } label: {
                if isSendingInput {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.turn.down.left")
                }
            }
            .frame(width: 42, height: 38)
            .foregroundStyle(theme.terminalAccent)
            .background(theme.buttonBackground, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
            .buttonStyle(.plain)
            .disabled(!canSendInput || commandDraft.isEmpty)
        }
    }

    private var shortcutEditorSheet: some View {
        SwiftTerminalShortcutEditorSheet(
            shortcutEditorDraft: $shortcutEditorDraft,
            shortcutEditorError: $shortcutEditorError,
            onClose: { showsShortcutEditor = false },
            onApply: { applyCustomShortcuts() },
            onReset: { shortcutEditorDraft = SwiftTerminalShortcut.defaultCustomJSON }
        )
    }

    private var pinnedShortcutPickerSheet: some View {
        SwiftTerminalPinnedShortcutPickerSheet(
            theme: theme,
            pinnedShortcuts: pinnedShortcuts,
            unpinnedSelectableShortcuts: unpinnedSelectableShortcuts,
            onTogglePinnedShortcut: { shortcut in togglePinnedShortcut(shortcut) },
            onMovePinnedShortcuts: { source, destination in movePinnedShortcuts(from: source, to: destination) },
            onClose: { showsPinnedShortcutPicker = false }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "terminal")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(theme.terminalAccent)
            Text(LocalizationManager.shared.localized("swift_terminal.no_pane"))
                .font(AppFont.title3(weight: .semibold))
                .foregroundStyle(theme.primaryText)
            Text(LocalizationManager.shared.localized("swift_terminal.no_pane_hint"))
                .font(AppFont.callout())
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button {
                createSwiftTerminal()
            } label: {
                if isCreatingTerminal { ProgressView() }
                Text(LocalizationManager.shared.localized("swift_terminal.create"))
                    .font(AppFont.body(weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .disabled(!codex.isConnected || isCreatingTerminal)
        }
        .padding(24)
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text(LocalizationManager.shared.localized("terminal.offline_banner"))
                .font(AppFont.caption(weight: .medium))
        }
        .foregroundStyle(theme.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(theme.panelBackground)
    }

    private var liveStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(selectedPaneTarget == nil ? theme.secondaryText.opacity(0.45) : theme.terminalAccent)
                .frame(width: 6, height: 6)
            Text(rendererMode.localizedShortTitle)
                .font(AppFont.caption2(weight: .semibold))
                .foregroundStyle(theme.secondaryText)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(theme.buttonBackground, in: Capsule())
    }

    private var displayedPanes: [ManagedTerminalPane] {
        codex.terminalPanes.filter { !isInternalBridgePane($0) }
    }

    private var selectedPane: ManagedTerminalPane? {
        if let selectedPaneTarget,
           let pane = displayedPanes.first(where: { paneMatches($0, target: selectedPaneTarget) }) {
            return pane
        }
        return preferredDefaultPane(in: displayedPanes)
    }

    private var currentSnapshot: ManagedTerminalSnapshot? {
        if let target = selectedPaneTarget,
           let snapshot = codex.terminalSnapshotsByPaneId[target] {
            return snapshot
        }
        guard let pane = selectedPane else { return nil }
        return codex.terminalSnapshotsByPaneId[pane.requestTarget]
            ?? codex.terminalSnapshotsByPaneId[pane.paneId]
            ?? codex.terminalSnapshotsByPaneId[pane.paneKey]
            ?? codex.terminalSnapshotsByPaneId[pane.paneAddress]
    }

    private var currentSnapshotText: String {
        if currentSnapshot?.content.isEmpty == false {
            return currentSnapshot?.content ?? ""
        }
        return selectedPane == nil
            ? LocalizationManager.shared.localized("terminal.snapshot.select_hint")
            : LocalizationManager.shared.localized("terminal.snapshot.loading")
    }

    private var currentSnapshotDisplayText: String {
        let sanitized = trimTerminalBlankEdges(sanitizedTerminalPlainText(from: currentSnapshotText))
        return sanitized.isEmpty ? " " : sanitized
    }

    private var currentSnapshotAttributedText: AttributedString {
        attributedTerminalText(from: currentSnapshotText)
    }

    private var paneTitleForHeader: String {
        if !paneTitle.isEmpty, paneTitle != "Swift", paneTitle != "Terminal" {
            return paneTitle
        }
        return selectedPane?.displayTitle ?? LocalizationManager.shared.localized("tab.terminal")
    }

    private var statusText: String {
        let sizeText = latestSize.map { "\($0.cols)x\($0.rows)" } ?? "--x--"
        if isSwiftTermRendererActive {
            let streamText = streamId?.suffix(8) ?? "no-stream"
            return "\(statusLine) · \(sizeText) · \(streamText)"
        }
        return "\(rendererMode.localizedTitle) · \(sizeText) · snapshot"
    }

    private var promptUserText: String {
        NSUserName().isEmpty ? "local" : NSUserName()
    }

    private var promptPathText: String {
        let cwd = selectedPane?.cwd.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !cwd.isEmpty else { return selectedPane?.sessionName ?? "terminal" }
        return URL(fileURLWithPath: cwd).lastPathComponent.nilIfEmpty ?? cwd
    }

    private var promptBranchText: String {
        let title = selectedPane?.windowName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.nilIfEmpty ?? "main"
    }

    private var streamMessages: [TerminalStreamMessage] {
        guard let streamId else { return [] }
        return codex.terminalStreamMessagesByStreamId[streamId] ?? []
    }

    private var canSendInput: Bool {
        codex.isConnected && selectedPaneTarget != nil && !isSendingInput
    }

    private var activeShortcuts: [SwiftTerminalShortcut] {
        switch shortcutProfile {
        case .compact:
            return SwiftTerminalShortcut.compactProfile
        case .agent:
            return SwiftTerminalShortcut.agentProfile
        case .shell:
            return SwiftTerminalShortcut.shellProfile
        case .mac:
            return SwiftTerminalShortcut.macProfile
        case .custom:
            return []
        }
    }

    private var displayedActiveShortcuts: [SwiftTerminalShortcut] {
        let pinnedIds = pinnedShortcutIds
        return activeShortcuts.filter { !pinnedIds.contains($0.pinId) }
    }

    private var pinnedShortcuts: [SwiftTerminalShortcut] {
        let orderedIds = pinnedShortcutIdList
        guard !orderedIds.isEmpty else { return [] }
        let shortcutByPinId = Dictionary(uniqueKeysWithValues: allSelectableShortcuts.map { ($0.pinId, $0) })
        let picked = orderedIds.compactMap { shortcutByPinId[$0] }
        return picked.isEmpty ? SwiftTerminalShortcut.defaultPinnedShortcuts : picked
    }

    private var unpinnedSelectableShortcuts: [SwiftTerminalShortcut] {
        let pinnedIds = pinnedShortcutIds
        return allSelectableShortcuts.filter { !pinnedIds.contains($0.pinId) }
    }

    private var allSelectableShortcuts: [SwiftTerminalShortcut] {
        var seen = Set<String>()
        var output = [SwiftTerminalShortcut]()
        let groups = [
            SwiftTerminalShortcut.defaultPinnedShortcuts,
            SwiftTerminalShortcut.compactProfile,
            SwiftTerminalShortcut.agentProfile,
            SwiftTerminalShortcut.shellProfile,
            SwiftTerminalShortcut.macProfile,
            decodedCustomShortcuts() ?? [],
        ]
        for shortcut in groups.flatMap({ $0 }) where seen.insert(shortcut.pinId).inserted {
            output.append(shortcut)
        }
        return output
    }

    private var pinnedShortcutIdList: [String] {
        if pinnedShortcutIdsRaw.trimmingCharacters(in: .whitespacesAndNewlines) == emptyPinnedShortcutSentinel {
            return []
        }
        let rawIds = pinnedShortcutIdsRaw
            .split(separator: "\n")
            .map(String.init)
        let sourceIds = rawIds.isEmpty
            ? SwiftTerminalShortcut.defaultPinnedShortcuts.map(\.pinId)
            : rawIds
        var seen = Set<String>()
        return sourceIds.compactMap(normalizedPinnedShortcutId)
            .filter { seen.insert($0).inserted }
    }

    private var pinnedShortcutIds: Set<String> {
        Set(pinnedShortcutIdList)
    }

    private var stablePollKey: String {
        "\(rendererModeRaw)|\(selectedPaneTarget ?? "-")|\(codex.isConnected)|\(scenePhase == .active)|\(terminalFontFamilyRaw)|\(useDarkTerminalCanvas)|\(fontSize)"
    }

    private var stableCanvasResetKey: String {
        "\(selectedPaneTarget ?? selectedPane?.requestTarget ?? "-")|\(terminalFontFamilyRaw)|\(useDarkTerminalCanvas)|\(colorScheme)|\(fontSize)"
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(get: { localErrorMessage != nil }, set: { if !$0 { localErrorMessage = nil } })
    }

    private var closeDialogIsPresented: Binding<Bool> {
        Binding(get: { pendingCloseRequest != nil }, set: { if !$0 { pendingCloseRequest = nil } })
    }

    private var closeDialogTitle: String {
        pendingCloseRequest?.title ?? LocalizationManager.shared.localized("terminal.dialog.close_title")
    }

    private var closeDialogMessage: String {
        pendingCloseRequest?.message ?? LocalizationManager.shared.localized("terminal.alert.error_message")
    }

    private var swiftTerminalBackground: Color {
        theme.terminalSurface
    }

    private var swiftTerminalPanel: Color {
        theme.panelBackground
    }

    private var swiftTerminalBorder: Color {
        theme.border
    }

    private func headerIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 38, height: 34)
            .background(theme.buttonBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .foregroundStyle(theme.buttonText)
    }

    private func promptChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(AppFont.mono(.caption2))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color)
    }

    private func refreshTerminals() {
        Task {
            await refreshTerminalsAsync()
            await refreshStableSnapshotIfNeeded()
        }
    }

    @MainActor
    private func primeTerminalOnEntry() async {
        guard codex.isConnected else { return }
        await refreshTerminalsAsync(preferUsefulDefault: true)
        if isSwiftTermRendererActive {
            startStream()
        } else {
            await refreshStableSnapshotIfNeeded()
        }
    }

    @MainActor
    private func refreshTerminalsAsync(preferUsefulDefault: Bool = false) async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            _ = try await codex.refreshTerminalList(showLoading: true)
            selectDefaultPaneIfNeeded(preferUsefulDefault: preferUsefulDefault)
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshStableSnapshotIfNeeded() async {
        guard !isSwiftTermRendererActive, codex.isConnected else { return }
        guard let target = selectedPaneTarget ?? selectedPane?.requestTarget else { return }
        await refreshStableSnapshot(target: target)
    }

    @MainActor
    private func refreshStableSnapshot(target: String) async {
        do {
            let snapshot = try await codex.refreshTerminalSnapshot(paneId: target, preserveAnsi: true, joinWrapped: false)
            statusLine = "stable"
            paneTitle = snapshot.pane.displayTitle
        } catch {
            if !Task.isCancelled {
                statusLine = "snapshot error"
                codex.terminalLastErrorMessage = nil
            }
        }
    }

    @MainActor
    private func pollStableSnapshotIfNeeded() async {
        guard !isSwiftTermRendererActive, codex.isConnected, scenePhase == .active else { return }
        guard let target = selectedPaneTarget ?? selectedPane?.requestTarget else { return }
        while !Task.isCancelled {
            guard !isSwiftTermRendererActive,
                  codex.isConnected,
                  scenePhase == .active,
                  target == (selectedPaneTarget ?? selectedPane?.requestTarget) else { return }
            await refreshStableSnapshot(target: target)
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func createSwiftTerminal() {
        Task {
            isCreatingTerminal = true
            defer { isCreatingTerminal = false }
            do {
                let list = try await codex.createManagedTerminal(
                    name: uniqueSwiftSessionName(),
                    cwd: newTerminalCwd,
                    command: nil,
                    cols: latestSize?.cols,
                    rows: latestSize?.rows,
                    openVisible: openVisibleTerminalOnCreate,
                    visibleApp: terminalVisibleApp.rpcValue
                )
                selectedPaneTarget = list.createdPane?.requestTarget ?? list.panes.first?.requestTarget
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func closeTerminal(_ request: SwiftTerminalCloseRequest) {
        let selectedWasClosed = request.matches(selectedPaneTarget)
        Task {
            do {
                switch request {
                case .pane(let pane):
                    try await codex.killTerminalPane(pane.requestTarget)
                case .session(let pane):
                    try await codex.killTerminalSession(pane.sessionName)
                }
                pendingCloseRequest = nil
                try? await Task.sleep(nanoseconds: 200_000_000)
                let list = try await codex.refreshTerminalList(showLoading: false)
                if selectedWasClosed || selectedPaneTarget == nil || !list.panes.contains(where: { paneMatches($0, target: selectedPaneTarget) }) {
                    selectedPaneTarget = list.panes.first?.requestTarget
                }
                await refreshStableSnapshotIfNeeded()
            } catch {
                pendingCloseRequest = nil
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func startStream() {
        guard isSwiftTermRendererActive else { return }
        guard codex.isConnected else { return }
        guard scenePhase == .active else { return }
        let pane = selectedPane
        guard let target = selectedPaneTarget ?? pane?.requestTarget else { return }
        guard let size = latestSize, size.cols > 10, size.rows > 5 else {
            statusLine = "sizing"
            return
        }
        let previousStreamId = streamId
        streamLifecycleToken += 1
        let token = streamLifecycleToken
        startStreamTask?.cancel()
        startStreamTask = Task {
            isStartingStream = true
            defer {
                if token == streamLifecycleToken {
                    isStartingStream = false
                    startStreamTask = nil
                }
            }
            do {
                if let previousStreamId {
                    try? await codex.stopTerminalStream(streamId: previousStreamId)
                }
                try Task.checkCancellation()
                let response = try await codex.startTerminalStream(
                    paneId: target,
                    cols: size.cols,
                    rows: size.rows,
                    replay: true,
                    replayViewportOnly: shouldUseViewportReplay(pane)
                )
                guard !Task.isCancelled, token == streamLifecycleToken else {
                    try? await codex.stopTerminalStream(streamId: response.streamId)
                    return
                }
                streamId = response.streamId
                statusLine = response.status
                lastStreamReconnectSignature = ""
            } catch is CancellationError {
                return
            } catch {
                if token == streamLifecycleToken {
                    localErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func handleActiveStreamRevision() {
        guard isSwiftTermRendererActive,
              codex.isConnected,
              scenePhase == .active,
              !isStartingStream,
              let failedStreamId = streamId,
              let status = codex.terminalStreamStatusByStreamId[failedStreamId],
              status.status == "error" || status.status == "exited" else {
            return
        }
        let signature = "\(failedStreamId):\(status.lastSeq):\(status.status)"
        guard signature != lastStreamReconnectSignature else { return }
        lastStreamReconnectSignature = signature
        let token = streamLifecycleToken
        streamId = nil
        statusLine = "reconnecting"
        Task { @MainActor in
            try? await codex.stopTerminalStream(streamId: failedStreamId)
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard token == streamLifecycleToken,
                  isSwiftTermRendererActive,
                  codex.isConnected,
                  scenePhase == .active,
                  !isStartingStream else {
                return
            }
            startStream()
        }
    }

    private func stopActiveStream(status: String, notifyBridge: Bool = true) {
        streamLifecycleToken += 1
        startStreamTask?.cancel()
        startStreamTask = nil
        isStartingStream = false
        guard let streamId else {
            statusLine = status
            return
        }
        self.streamId = nil
        statusLine = status
        guard notifyBridge, codex.isConnected else { return }
        Task {
            try? await codex.stopTerminalStream(streamId: streamId)
        }
    }

    private func sendCommandFromDraft() {
        let command = commandDraft.trimmingCharacters(in: .newlines)
        guard !command.isEmpty else { return }
        guard let target = selectedPaneTarget else { return }
        guard !shouldSuppressInput(signature: "command:\(target):\(command)", interval: 0.35) else { return }
        commandDraft = ""
        Task {
            isSendingInput = true
            defer { isSendingInput = false }
            do {
                try await codex.sendTerminalText(command, paneId: target)
                try await codex.sendTerminalKey(.enter, paneId: target)
                scheduleStableRefresh(target: target)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func sendShortcut(_ shortcut: SwiftTerminalShortcut) {
        suppressKeyboardForVirtualShortcut()
        switch shortcut.kind {
        case .key:
            guard let keyValue = ManagedTerminalKey.swiftTerminalKeyValue(from: shortcut.value) else {
                localErrorMessage = String(format: LocalizationManager.shared.localized("swift_terminal.shortcuts_bad_key"), shortcut.value)
                return
            }
            sendKeyValue(keyValue)
        case .text:
            sendText(shortcut.value)
        case .bytes:
            let data = Data(base64Encoded: shortcut.value) ?? Data(shortcut.value.utf8)
            sendTerminalData(data)
        case .action:
            guard let action = SwiftTerminalShortcutAction(shortcut.value) else {
                localErrorMessage = String(format: LocalizationManager.shared.localized("swift_terminal.shortcuts_bad_action"), shortcut.value)
                return
            }
            performShortcutAction(action)
        }
    }

    private func togglePinnedShortcut(_ shortcut: SwiftTerminalShortcut) {
        var ids = pinnedShortcutIdList
        if let existingIndex = ids.firstIndex(of: shortcut.pinId) {
            ids.remove(at: existingIndex)
        } else {
            ids.append(shortcut.pinId)
        }
        storePinnedShortcutIds(ids)
    }

    private func movePinnedShortcuts(from source: IndexSet, to destination: Int) {
        var ids = pinnedShortcutIdList
        ids.move(fromOffsets: source, toOffset: destination)
        storePinnedShortcutIds(ids)
    }

    private func storePinnedShortcutIds(_ ids: [String]) {
        pinnedShortcutIdsRaw = ids.isEmpty ? emptyPinnedShortcutSentinel : ids.joined(separator: "\n")
    }

    private func normalizedPinnedShortcutId(_ storedId: String) -> String? {
        allSelectableShortcuts.first { shortcut in
            storedId == shortcut.pinId
                || storedId == shortcut.id
                || (storedId.hasPrefix("\(shortcut.kind.rawValue):") && storedId.hasSuffix(":\(shortcut.value)"))
        }?.pinId
    }

    private func sendTerminalData(_ data: Data) {
        guard let target = selectedPaneTarget, !data.isEmpty else { return }
        if isLineEndingData(data) {
            guard !shouldSuppressInput(signature: "bytes:\(target):enter", interval: 0.35) else { return }
        } else if isPasteLikeTextData(data) {
            guard !shouldSuppressInput(signature: "bytes:\(target):paste:\(data.base64EncodedString())", interval: 0.16) else { return }
        }
        Task {
            do {
                try await codex.sendTerminalData(data, paneId: target)
                scheduleStableRefresh(target: target)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func sendText(_ text: String) {
        guard let target = selectedPaneTarget, !text.isEmpty else { return }
        guard !shouldSuppressInput(signature: "text:\(target):\(text)", interval: 0.25) else { return }
        Task {
            do {
                if text.contains("\n") || text.contains("\r") {
                    try await codex.sendTerminalData(Data(text.utf8), paneId: target)
                } else {
                    try await codex.sendTerminalText(text, paneId: target)
                }
                scheduleStableRefresh(target: target)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func sendKey(_ key: ManagedTerminalKey) {
        sendKeyValue(key.rawValue)
    }

    private func toggleChordModifier(_ modifier: SwiftTerminalChordModifier) {
        if selectedChordModifiers.contains(modifier) {
            selectedChordModifiers.remove(modifier)
        } else {
            selectedChordModifiers.insert(modifier)
        }
    }

    private var chordModifierGlyphText: String {
        let labels = SwiftTerminalChordModifier.allCases
            .filter { selectedChordModifiers.contains($0) }
            .map(\.label)
        return labels.joined()
    }

    private var chordPreviewGlyphText: String {
        let glyphs = chordModifierGlyphText
        guard let key = selectedChordPreviewKey else {
            return glyphs.isEmpty ? "⌘K" : "\(glyphs)…"
        }
        return "\(glyphs)\(key.label)"
    }

    private var chordPreviewValueText: String {
        guard let key = selectedChordPreviewKey else {
            let prefixes = selectedChordModifierPrefixes
            guard !prefixes.isEmpty else {
                return LocalizationManager.shared.localized("swift_terminal.chord_preview_empty")
            }
            return (prefixes + ["..."]).joined(separator: "-")
        }
        return composedChordValue(for: key)
    }

    private var selectedChordModifierPrefixes: [String] {
        SwiftTerminalChordModifier.allCases
            .filter { selectedChordModifiers.contains($0) }
            .map(\.keyPrefix)
    }

    private func openChordComposer() {
        prepareShortcutSheetPresentation {
            chordModeEnabled = true
            selectedChordPreviewKey = nil
            showsChordComposer = true
            suppressKeyboardForChordComposerRepeatedly()
        }
    }

    private func openPinnedShortcutPicker() {
        prepareShortcutSheetPresentation {
            showsPinnedShortcutPicker = true
        }
    }

    private func openShortcutEditor() {
        shortcutEditorDraft = customShortcutsJSON
        shortcutEditorError = nil
        showsShortcutEditor = true
    }

    private func toggleKeyBarExpanded() {
        if keyBarExpanded {
            keyBarExpanded = false
        } else {
            hideTerminalKeyboard()
            keyBarExpanded = true
        }
    }

    private func prepareShortcutSheetPresentation(_ present: @escaping @MainActor () -> Void) {
        hideTerminalKeyboard()
        keyBarExpanded = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            present()
        }
    }

    private func sendChordKey(_ key: SwiftTerminalChordKey) {
        suppressKeyboardForVirtualShortcut()
        selectedChordPreviewKey = key
        if selectedChordModifiers.isEmpty {
            sendUnmodifiedChordKey(key)
            return
        }

        sendKeyValue(composedChordValue(for: key))
    }

    private func composedChordValue(for key: SwiftTerminalChordKey) -> String {
        guard !selectedChordModifiers.isEmpty else { return key.value }
        return (selectedChordModifierPrefixes + [key.value]).joined(separator: "-")
    }

    private func sendUnmodifiedChordKey(_ key: SwiftTerminalChordKey) {
        if let textValue = key.textValue {
            sendText(textValue)
        } else {
            sendKeyValue(key.value)
        }
    }

    private func sendKeyValue(_ keyValue: String) {
        guard let normalizedKey = ManagedTerminalKey.swiftTerminalKeyValue(from: keyValue) else {
            localErrorMessage = String(format: LocalizationManager.shared.localized("swift_terminal.shortcuts_bad_key"), keyValue)
            return
        }
        if !isSwiftTermRendererActive {
            if normalizedKey == ManagedTerminalKey.enter.rawValue, !commandDraft.isEmpty {
                sendCommandFromDraft()
                return
            }
            if normalizedKey == ManagedTerminalKey.backspace.rawValue, !commandDraft.isEmpty {
                commandDraft.removeLast()
                return
            }
        }
        guard let target = selectedPaneTarget else { return }
        guard !shouldSuppressInput(signature: "key:\(target):\(normalizedKey)", interval: normalizedKey == ManagedTerminalKey.enter.rawValue ? 0.35 : 0.18) else { return }
        Task {
            do {
                try await codex.sendTerminalKeyValue(normalizedKey, paneId: target)
                scheduleStableRefresh(target: target)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func performShortcutAction(_ action: SwiftTerminalShortcutAction) {
        switch action {
        case .copy:
            copyTerminal()
        case .paste:
            pasteClipboard()
        case .focus:
            focusTerminalInput()
        case .hideKeyboard:
            hideTerminalKeyboard()
        case .top:
            pageUpOrTop()
        case .bottom:
            pageDownOrBottom()
        case .reset:
            resetTerminalView()
        }
    }

    private func pasteClipboard() {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        let payload = bracketedPaste
            ? "\u{001B}[200~\(text)\u{001B}[201~"
            : text
        sendTerminalData(Data(payload.utf8))
    }

    private func copyTerminal() {
        if isSwiftTermRendererActive {
            copyRequestID += 1
        } else {
            UIPasteboard.general.string = currentSnapshotDisplayText
        }
    }

    private func focusTerminalInput() {
        guard !showsChordComposer else {
            suppressKeyboardForChordComposer()
            return
        }
        keyBarExpanded = false
        if isSwiftTermRendererActive {
            focusRequestID += 1
        } else {
            isCommandFieldFocused = true
        }
    }

    private func hideTerminalKeyboard() {
        if isSwiftTermRendererActive {
            blurRequestID += 1
        } else {
            isCommandFieldFocused = false
        }
        dismissActiveKeyboard()
    }

    private func dismissActiveKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func suppressKeyboardForChordComposer() {
        keyBarExpanded = false
        isCommandFieldFocused = false
        if isSwiftTermRendererActive {
            blurRequestID += 1
        }
        dismissActiveKeyboard()
    }

    private func suppressKeyboardForVirtualShortcut() {
        isCommandFieldFocused = false
        if isSwiftTermRendererActive {
            blurRequestID += 1
        }
        dismissActiveKeyboard()
    }

    private func suppressKeyboardForChordComposerRepeatedly() {
        suppressKeyboardForChordComposer()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            if showsChordComposer {
                suppressKeyboardForChordComposer()
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
            if showsChordComposer {
                suppressKeyboardForChordComposer()
            }
        }
    }

    private func pageUpOrTop() {
        selectAdjacentPane(offset: -1)
    }

    private func pageDownOrBottom() {
        selectAdjacentPane(offset: 1)
    }

    private func selectAdjacentPane(offset: Int) {
        let panes = displayedPanes
        guard panes.count > 1 else { return }
        hideTerminalKeyboard()
        let currentIndex = panes.firstIndex { paneMatches($0, target: selectedPaneTarget) } ?? 0
        let nextIndex = (currentIndex + offset + panes.count) % panes.count
        selectedPaneTarget = panes[nextIndex].requestTarget
    }

    private func resetTerminalView() {
        if isSwiftTermRendererActive {
            resetRequestID += 1
        } else {
            stableScrollBottomRequestID += 1
            Task { await refreshStableSnapshotIfNeeded() }
        }
    }

    private func resizeTerminal(cols: Int, rows: Int) {
        guard rows > 5 else {
            statusLine = "keyboard"
            return
        }
        latestSize = (cols, rows)
        guard let target = selectedPaneTarget else { return }
        Task {
            do {
                try await codex.resizeTerminalPane(paneId: target, cols: cols, rows: rows)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
        if isSwiftTermRendererActive, streamId == nil, !isStartingStream, codex.isConnected, scenePhase == .active {
            startStream()
        }
    }

    private func resizeStableTerminalIfNeeded(size: CGSize) {
        guard !isSwiftTermRendererActive else { return }
        let dims = stableTerminalDimensions(for: size)
        guard latestSize?.cols != dims.cols || latestSize?.rows != dims.rows else { return }
        latestSize = dims
        guard let target = selectedPaneTarget else { return }
        Task {
            do {
                try await codex.resizeTerminalPane(paneId: target, cols: dims.cols, rows: dims.rows)
                await refreshStableSnapshot(target: target)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func stableTerminalDimensions(for size: CGSize) -> (cols: Int, rows: Int) {
        let charWidth = max(5.6, fontSize * 0.60)
        let rowHeight = max(12.0, fontSize * 1.25)
        return (
            cols: max(40, min(140, Int(max(size.width - 28, 1) / charWidth))),
            rows: max(8, min(90, Int(max(size.height - 30, 1) / rowHeight)))
        )
    }

    private func scheduleStableRefresh(target: String?) {
        guard !isSwiftTermRendererActive, let target else { return }
        Task {
            try? await Task.sleep(nanoseconds: 160_000_000)
            await refreshStableSnapshot(target: target)
            await MainActor.run {
                if target == selectedPaneTarget {
                    stableScrollBottomRequestID += 1
                }
            }
        }
    }

    private func shouldSuppressInput(signature: String, interval: TimeInterval) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        defer {
            lastInputSignature = signature
            lastInputAt = now
        }
        return signature == lastInputSignature && now - lastInputAt < interval
    }

    private func isLineEndingData(_ data: Data) -> Bool {
        data == Data([0x0A]) || data == Data([0x0D]) || data == Data([0x0D, 0x0A])
    }

    private func isPasteLikeTextData(_ data: Data) -> Bool {
        guard data.count > 1,
              data.first != 0x1B,
              !data.contains(where: { $0 < 0x20 || $0 == 0x7F }),
              String(data: data, encoding: .utf8) != nil else {
            return false
        }
        return true
    }

    private func decodedCustomShortcuts() -> [SwiftTerminalShortcut]? {
        guard let data = customShortcutsJSON.data(using: .utf8),
              let shortcuts = try? JSONDecoder().decode([SwiftTerminalShortcut].self, from: data),
              !shortcuts.isEmpty,
              validateShortcuts(shortcuts) == nil else {
            return nil
        }
        return shortcuts
    }

    private func applyCustomShortcuts() {
        guard let data = shortcutEditorDraft.data(using: .utf8) else { return }
        do {
            let shortcuts = try JSONDecoder().decode([SwiftTerminalShortcut].self, from: data)
            guard !shortcuts.isEmpty else {
                shortcutEditorError = LocalizationManager.shared.localized("swift_terminal.shortcuts_empty")
                return
            }
            if let validationError = validateShortcuts(shortcuts) {
                shortcutEditorError = validationError
                return
            }
            let encoded = try JSONEncoder.swiftTerminalPretty.encode(shortcuts)
            customShortcutsJSON = String(data: encoded, encoding: .utf8) ?? shortcutEditorDraft
            shortcutProfileRaw = SwiftTerminalShortcutProfile.custom.rawValue
            showsShortcutEditor = false
        } catch {
            shortcutEditorError = error.localizedDescription
        }
    }

    private func validateShortcuts(_ shortcuts: [SwiftTerminalShortcut]) -> String? {
        for shortcut in shortcuts {
            let label = shortcut.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = shortcut.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if label.isEmpty || value.isEmpty {
                return LocalizationManager.shared.localized("swift_terminal.shortcuts_bad_item")
            }
            if shortcut.kind == .key, ManagedTerminalKey.swiftTerminalKeyValue(from: shortcut.value) == nil {
                return String(format: LocalizationManager.shared.localized("swift_terminal.shortcuts_bad_key"), shortcut.value)
            }
            if shortcut.kind == .action, SwiftTerminalShortcutAction(shortcut.value) == nil {
                return String(format: LocalizationManager.shared.localized("swift_terminal.shortcuts_bad_action"), shortcut.value)
            }
        }
        return nil
    }

    private func enforceStableRendererDefaultIfNeeded() {
        if stableDefaultRevision < stableFallbackRevision || SwiftTerminalRendererMode(rawValue: rendererModeRaw) == nil {
            rendererModeRaw = SwiftTerminalRendererMode.stable.rawValue
            stableDefaultRevision = stableFallbackRevision
            stopActiveStream(status: "stable")
        }
    }

    private func selectDefaultPaneIfNeeded(preferUsefulDefault: Bool = false) {
        let preferred = preferredDefaultPane(in: displayedPanes)
        if let selectedPaneTarget,
           let currentPane = displayedPanes.first(where: { paneMatches($0, target: selectedPaneTarget) }) {
            if preferUsefulDefault,
               let preferred,
               !paneMatches(preferred, target: selectedPaneTarget),
               paneDefaultScore(preferred) >= paneDefaultScore(currentPane) + 200 {
                self.selectedPaneTarget = preferred.requestTarget
            }
            return
        }
        selectedPaneTarget = preferred?.requestTarget
    }

    private func preferredDefaultPane(in panes: [ManagedTerminalPane]) -> ManagedTerminalPane? {
        panes.max { lhs, rhs in
            let lhsScore = paneDefaultScore(lhs)
            let rhsScore = paneDefaultScore(rhs)
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            return tmuxObjectNumber(lhs.requestTarget) < tmuxObjectNumber(rhs.requestTarget)
        }
    }

    private func paneDefaultScore(_ pane: ManagedTerminalPane) -> Int {
        let haystack = [
            pane.title,
            pane.currentCommand,
            pane.windowName,
            pane.sessionName,
            pane.cwd,
        ].joined(separator: " ").lowercased()
        let command = pane.currentCommand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let shellCommands = Set(["", "sh", "bash", "zsh", "fish", "tmux", "login"])
        var score = pane.active ? 20 : 0

        if command == "python" && pane.title.contains("✳") { score += 520 }
        if haystack.contains("claude") || haystack.contains("codex") { score += 460 }
        if !shellCommands.contains(command) { score += 260 }
        if !pane.cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 30 }
        return score
    }

    private func isInternalBridgePane(_ pane: ManagedTerminalPane) -> Bool {
        pane.sessionName == "mms-remote-swiftterm-bridge"
    }

    private func tmuxObjectNumber(_ value: String) -> Int {
        Int(value.filter(\.isNumber)) ?? Int.min
    }

    private func paneMatches(_ pane: ManagedTerminalPane, target: String?) -> Bool {
        pane.matches(target: target)
    }

    private func uniqueSwiftSessionName() -> String {
        "terminal-\(Int(Date().timeIntervalSince1970))"
    }

    private func shouldUseViewportReplay(_ pane: ManagedTerminalPane?) -> Bool {
        guard let pane else { return false }
        let text = [
            pane.title,
            pane.currentCommand,
            pane.windowName,
            pane.sessionName,
        ].joined(separator: " ").lowercased()
        let agentMarkers = ["claude", "codex"]
        if agentMarkers.contains(where: { text.contains($0) }) {
            return false
        }
        let tuiMarkers = ["vim", "nvim", "less", "top", "htop"]
        return tuiMarkers.contains { text.contains($0) }
    }

    private func trimTerminalBlankEdges(_ text: String) -> String {
        TerminalTextUtilities.trimBlankEdges(text)
    }

    private func sanitizedTerminalPlainText(from text: String) -> String {
        sanitizeTerminalDisplayText(stripTerminalEscapeSequences(from: text))
    }

    private func attributedTerminalText(from text: String) -> AttributedString {
        let source = trimTerminalBlankEdgesPreservingAnsi(text)
        let plain = trimTerminalBlankEdges(sanitizedTerminalPlainText(from: source))
        let defaultStyle = SwiftTerminalANSIStyle(foreground: theme.terminalText)
        guard !plain.isEmpty else {
            return styledTerminalRun(" ", style: defaultStyle)
        }

        var output = AttributedString()
        var style = defaultStyle
        var buffer = ""
        var index = source.startIndex

        while index < source.endIndex {
            if source[index] == "\u{001B}" {
                appendStyledTerminalBuffer(&buffer, style: style, to: &output)
                index = applyTerminalEscape(in: source, from: index, style: &style)
                continue
            }

            appendSanitizedTerminalCharacter(source[index], to: &buffer)
            index = source.index(after: index)
        }

        appendStyledTerminalBuffer(&buffer, style: style, to: &output)
        return output.characters.isEmpty ? styledTerminalRun(" ", style: SwiftTerminalANSIStyle(foreground: theme.terminalText)) : output
    }

    private func appendStyledTerminalBuffer(_ buffer: inout String, style: SwiftTerminalANSIStyle, to output: inout AttributedString) {
        guard !buffer.isEmpty else { return }
        output += styledTerminalRun(buffer, style: style)
        buffer.removeAll(keepingCapacity: true)
    }

    private func styledTerminalRun(_ text: String, style: SwiftTerminalANSIStyle) -> AttributedString {
        var run = AttributedString(text)
        run.foregroundColor = style.foreground
        if let background = style.background {
            run.backgroundColor = background
        }
        if style.bold {
            run.inlinePresentationIntent = .stronglyEmphasized
        }
        return run
    }

    private func appendSanitizedTerminalCharacter(_ character: Character, to output: inout String) {
        TerminalTextUtilities.appendSanitizedCharacter(character, to: &output)
    }

    private func stripTerminalEscapeSequences(from text: String) -> String {
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\u{001B}" {
                index = consumeTerminalEscape(in: text, from: index)
                continue
            }
            appendSanitizedTerminalCharacter(text[index], to: &output)
            index = text.index(after: index)
        }
        return output
    }

    private func trimTerminalBlankEdgesPreservingAnsi(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        func hasVisibleText(_ line: String) -> Bool {
            !sanitizedTerminalPlainText(from: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        while lines.count > 1,
              lines.first.map({ !hasVisibleText($0) }) == true,
              lines.contains(where: hasVisibleText) {
            lines.removeFirst()
        }
        while lines.count > 1,
              lines.last.map({ !hasVisibleText($0) }) == true,
              lines.contains(where: hasVisibleText) {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private func applyTerminalEscape(in text: String, from start: String.Index, style: inout SwiftTerminalANSIStyle) -> String.Index {
        var index = text.index(after: start)
        guard index < text.endIndex else { return index }
        guard text[index] == "[" else {
            return consumeTerminalEscape(in: text, from: start)
        }

        index = text.index(after: index)
        let parameterStart = index
        while index < text.endIndex {
            let value = text[index].unicodeScalars.first?.value ?? 0
            if (0x40...0x7E).contains(value) {
                let parameters = String(text[parameterStart..<index])
                let final = text[index]
                let next = text.index(after: index)
                if final == "m" {
                    applySGRParameters(parameters, to: &style)
                }
                return next
            }
            index = text.index(after: index)
        }
        return index
    }

    private func consumeTerminalEscape(in text: String, from start: String.Index) -> String.Index {
        var index = text.index(after: start)
        guard index < text.endIndex else { return index }

        if text[index] == "[" {
            index = text.index(after: index)
            while index < text.endIndex {
                let value = text[index].unicodeScalars.first?.value ?? 0
                index = text.index(after: index)
                if (0x40...0x7E).contains(value) {
                    return index
                }
            }
            return index
        }

        if text[index] == "]" {
            index = text.index(after: index)
            while index < text.endIndex {
                if text[index] == "\u{0007}" {
                    return text.index(after: index)
                }
                if text[index] == "\u{001B}" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\\" {
                        return text.index(after: next)
                    }
                }
                index = text.index(after: index)
            }
            return index
        }

        return text.index(after: index)
    }

    private func applySGRParameters(_ parameters: String, to style: inout SwiftTerminalANSIStyle) {
        let normalized = parameters.replacingOccurrences(of: ":", with: ";")
        let values = normalized
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        let codes = values.isEmpty ? [0] : values
        var index = 0

        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0:
                style = SwiftTerminalANSIStyle(foreground: theme.terminalText)
            case 1:
                style.bold = true
            case 22:
                style.bold = false
            case 30...37:
                style.foreground = ansiTerminalColor(code - 30, bright: false)
            case 90...97:
                style.foreground = ansiTerminalColor(code - 90, bright: true)
            case 39:
                style.foreground = theme.terminalText
            case 40...47:
                style.background = ansiTerminalColor(code - 40, bright: false).opacity(0.70)
            case 100...107:
                style.background = ansiTerminalColor(code - 100, bright: true).opacity(0.70)
            case 49:
                style.background = nil
            case 38, 48:
                let isForeground = code == 38
                if let parsed = extendedANSIColor(from: codes, startingAt: index + 1) {
                    if isForeground {
                        style.foreground = parsed.color
                    } else {
                        style.background = parsed.color.opacity(0.70)
                    }
                    index = parsed.nextIndex - 1
                }
            default:
                break
            }
            index += 1
        }
    }

    private func extendedANSIColor(from codes: [Int], startingAt index: Int) -> (color: Color, nextIndex: Int)? {
        guard index < codes.count else { return nil }
        if codes[index] == 5, index + 1 < codes.count {
            return (xterm256Color(codes[index + 1]), index + 2)
        }
        if codes[index] == 2, index + 3 < codes.count {
            return (
                Color(
                    red: Double(max(0, min(255, codes[index + 1]))) / 255.0,
                    green: Double(max(0, min(255, codes[index + 2]))) / 255.0,
                    blue: Double(max(0, min(255, codes[index + 3]))) / 255.0
                ),
                index + 4
            )
        }
        return nil
    }

    private func xterm256Color(_ value: Int) -> Color {
        let clamped = max(0, min(255, value))
        if clamped < 16 {
            return ansiTerminalColor(clamped % 8, bright: clamped >= 8)
        }
        if clamped <= 231 {
            let offset = clamped - 16
            let red = offset / 36
            let green = (offset % 36) / 6
            let blue = offset % 6
            return Color(
                red: xtermColorComponent(red),
                green: xtermColorComponent(green),
                blue: xtermColorComponent(blue)
            )
        }
        let gray = Double(8 + (clamped - 232) * 10) / 255.0
        return Color(red: gray, green: gray, blue: gray)
    }

    private func xtermColorComponent(_ value: Int) -> Double {
        value == 0 ? 0.0 : Double(55 + value * 40) / 255.0
    }

    private func ansiTerminalColor(_ index: Int, bright: Bool) -> Color {
        let normal = [
            Color(red: 0.18, green: 0.20, blue: 0.23),
            Color(red: 0.86, green: 0.25, blue: 0.28),
            Color(red: 0.45, green: 0.78, blue: 0.36),
            Color(red: 0.87, green: 0.66, blue: 0.28),
            Color(red: 0.33, green: 0.56, blue: 0.93),
            Color(red: 0.76, green: 0.42, blue: 0.89),
            Color(red: 0.30, green: 0.78, blue: 0.83),
            Color(red: 0.82, green: 0.91, blue: 0.86),
        ]
        let brightColors = [
            Color(red: 0.45, green: 0.49, blue: 0.54),
            Color(red: 1.00, green: 0.38, blue: 0.40),
            Color(red: 0.64, green: 0.93, blue: 0.55),
            Color(red: 1.00, green: 0.81, blue: 0.41),
            Color(red: 0.46, green: 0.70, blue: 1.00),
            Color(red: 0.92, green: 0.58, blue: 1.00),
            Color(red: 0.50, green: 0.93, blue: 0.95),
            Color(red: 0.95, green: 0.98, blue: 0.92),
        ]
        return (bright ? brightColors : normal)[max(0, min(7, index))]
    }

    private func sanitizeTerminalDisplayText(_ text: String) -> String {
        TerminalTextUtilities.sanitizeDisplayText(text)
    }

    private func isTerminalControlScalar(_ scalar: UnicodeScalar) -> Bool {
        TerminalTextUtilities.isControlScalar(scalar)
    }

    private func isUnsupportedTerminalDisplayScalar(_ scalar: UnicodeScalar) -> Bool {
        TerminalTextUtilities.isUnsupportedDisplayScalar(scalar)
    }
}

private struct SwiftTerminalANSIStyle {
    var foreground: Color
    var background: Color?
    var bold: Bool

    init(foreground: Color, background: Color? = nil, bold: Bool = false) {
        self.foreground = foreground
        self.background = background
        self.bold = bold
    }
}

private extension JSONEncoder {
    static var swiftTerminalPretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
