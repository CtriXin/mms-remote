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

    var paneSheetRequestID = 0
    var showsPaneToolbarButton = true
    var onOpenSettings: (() -> Void)? = nil

    @AppStorage("swiftTerminal.fontSize") private var defaultFontSize = 12.0
    @AppStorage("swiftTerminal.bracketedPaste") private var bracketedPaste = true
    @AppStorage("swiftTerminal.bracketedPasteDefaultRevision") private var bracketedPasteDefaultRevision = 0
    @AppStorage("swiftTerminal.rendererMode") private var rendererModeRaw = SwiftTerminalRendererMode.stable.rawValue
    @AppStorage("swiftTerminal.shortcutProfile") private var shortcutProfileRaw = SwiftTerminalShortcutProfile.agent.rawValue
    @AppStorage("swiftTerminal.customShortcutsJSON") private var customShortcutsJSON = SwiftTerminalShortcut.defaultCustomJSON
    @AppStorage("swiftTerminal.pinnedShortcutIds") private var pinnedShortcutIdsRaw = SwiftTerminalShortcut.defaultPinnedIds
    @AppStorage("swiftTerminal.stableDefaultRevision") private var stableDefaultRevision = 0
    @AppStorage("swiftTerminal.swiftTermRestoreRevision") private var swiftTermRestoreRevision = 0
    @AppStorage("swiftTerminal.chordMode") private var chordModeEnabled = false
    @AppStorage(TerminalFontFamily.storageKey) private var terminalFontFamilyRaw = TerminalFontFamily.defaultStoredRawValue
    @AppStorage("terminal.darkCanvas") private var useDarkTerminalCanvas = true
    @AppStorage(TerminalVisibleAppPreference.storageKey) private var terminalVisibleAppRaw = TerminalVisibleAppPreference.defaultStoredRawValue
    @AppStorage("terminal.openVisibleOnCreate") private var openVisibleTerminalOnCreate = false

    @State private var keyBarExpanded = false
    @State private var sessionFontSizeOverride: Double?
    @State private var isKeyboardPresented = false
    @State private var isControlModifierLatched = false
    @State private var isMetaModifierLatched = false
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
    @State private var isShowingCreateTerminalSheet = false
    @State private var localErrorMessage: String?
    @State private var commandDraft = ""
    @State private var newTerminalName = ""
    @State private var newTerminalCwd = "/"
    @State private var createOpenVisibleOnMac = false
    @State private var createVisibleAppRaw = TerminalVisibleAppPreference.defaultStoredRawValue
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
    @State private var swiftTermInputReplayTask: Task<Void, Never>?
    @State private var shortcutEditorDraft = SwiftTerminalShortcut.defaultCustomJSON
    @State private var shortcutEditorError: String?
    @State private var showsShortcutEditor = false
    @State private var showsPinnedShortcutPicker = false
    @State private var isShowingTerminalPaneSheet = false
    @State private var pendingCloseRequest: SwiftTerminalCloseRequest?
    @State private var lastInputSignature = ""
    @State private var lastInputAt: TimeInterval = 0
    @State private var lastStreamReconnectSignature = ""
    @State private var pendingStreamStartSignature = ""
    @State private var activeStreamSignature = ""
    @FocusState private var isCommandFieldFocused: Bool
    private let stableFallbackRevision = 1
    private let swiftTermRestoreRevisionTarget = 1
    private let bracketedPasteDefaultRevisionTarget = 1
    private let allowsSwiftTermRenderer = true
    private let replaysSwiftTermAfterInput = false
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
        allowsSwiftTermRenderer && rendererMode == .swiftTerm
    }

    private var theme: SwiftTerminalTheme {
        SwiftTerminalTheme.resolve(systemScheme: colorScheme, useDarkTerminalCanvas: useDarkTerminalCanvas)
    }

    private var terminalVisibleApp: TerminalVisibleAppPreference {
        TerminalVisibleAppPreference(rawValue: terminalVisibleAppRaw) ?? .auto
    }

    private var createVisibleApp: TerminalVisibleAppPreference {
        TerminalVisibleAppPreference(rawValue: createVisibleAppRaw) ?? terminalVisibleApp
    }

    private var effectiveFontSize: Double {
        sessionFontSizeOverride ?? defaultFontSize
    }

    var body: some View {
        terminalContent
        .navigationTitle(LocalizationManager.shared.localized("tab.terminal"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(theme.isDark ? .dark : .light, for: .navigationBar)
        .toolbar {
            if showsPaneToolbarButton {
                ToolbarItem(placement: .topBarLeading) {
                    terminalPaneMenu
                }
            }
            ToolbarItem(placement: .principal) {
                terminalToolbarTitle
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                terminalRendererMenu
                terminalCreateButton
                terminalRefreshButton
            }
        }
        .task {
            enforceStableRendererDefaultIfNeeded()
            enableBracketedPasteByDefaultIfNeeded()
            await primeTerminalOnEntry()
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
                if isSwiftTermRendererActive {
                    startStream()
                } else {
                    await refreshStableSnapshotIfNeeded()
                }
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
        .onChange(of: paneSheetRequestID) { _, requestID in
            guard requestID > 0 else { return }
            openPanePicker()
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
        .sheet(isPresented: $isShowingTerminalPaneSheet) {
            SwiftTerminalPanePickerSheet(
                panes: displayedPanes,
                selectedPaneTarget: selectedPaneTarget,
                isConnected: codex.isConnected,
                isRefreshing: isRefreshing || isStartingStream,
                isCreatingTerminal: isCreatingTerminal,
                theme: theme,
                onSelectPane: { pane in
                    selectedPaneTarget = pane.requestTarget
                    isShowingTerminalPaneSheet = false
                },
                onCreate: {
                    isShowingTerminalPaneSheet = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 140_000_000)
                        openCreateTerminalSheet()
                    }
                },
                onRefresh: {
                    isSwiftTermRendererActive ? startStream(force: true) : refreshTerminals()
                },
                onCopyJoin: copyJoinCommand(for:),
                onCopyAddress: { pane in
                    UIPasteboard.general.string = pane.paneAddress
                },
                onClosePane: { pane in
                    isShowingTerminalPaneSheet = false
                    pendingCloseRequest = .pane(pane)
                },
                onCloseSession: { pane in
                    isShowingTerminalPaneSheet = false
                    pendingCloseRequest = .session(pane)
                },
                onOpenSettings: onOpenSettings.map { openSettings in
                    {
                        isShowingTerminalPaneSheet = false
                        openSettings()
                    }
                }
            )
        }
        .sheet(isPresented: $isShowingCreateTerminalSheet) {
            SwiftTerminalCreateSheet(
                name: $newTerminalName,
                cwd: $newTerminalCwd,
                openVisibleOnMac: $createOpenVisibleOnMac,
                visibleAppRaw: $createVisibleAppRaw,
                isCreating: isCreatingTerminal,
                onCreate: createSwiftTerminal
            )
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
            isKeyboardPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardPresented = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            isKeyboardPresented = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwiftTerm.TerminalView.controlModifierReset"))) { _ in
            isControlModifierLatched = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwiftTerm.TerminalView.metaModifierReset"))) { _ in
            isMetaModifierLatched = false
        }
    }

    private var terminalContent: some View {
        VStack(spacing: 0) {
            Group {
                if !codex.isConnected {
                    offlineBanner
                }
                terminalCanvas
                if showsChordComposer {
                    Divider().overlay(swiftTerminalBorder)
                    chordComposerPanel
                }
            }
            .background(theme.shellBackground)
            Divider().overlay(swiftTerminalBorder)
            keyBar
        }
        .background(theme.shellBackground.ignoresSafeArea(edges: .top))
    }

    private var terminalToolbarTitle: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(paneTitleForHeader)
                .font(AppFont.headline())
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                copySelectedPaneJoinCommand()
            } label: {
                Text(terminalHeaderDetailText)
                    .font(AppFont.mono(.caption2))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .allowsTightening(true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .contextMenu {
                if let selectedPane {
                    Button {
                        copyJoinCommand(for: selectedPane)
                    } label: {
                        Label(LocalizationManager.shared.localized("terminal.context.copy_join"), systemImage: "terminal")
                    }
                    Button {
                        UIPasteboard.general.string = selectedPane.paneAddress
                    } label: {
                        Label(LocalizationManager.shared.localized("terminal.context.copy_address"), systemImage: "number")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var terminalPaneMenu: some View {
        Button {
            openPanePicker()
        } label: {
            terminalToolbarIcon("rectangle.stack")
        }
        .disabled(displayedPanes.isEmpty)
    }

    private func openPanePicker() {
        guard !displayedPanes.isEmpty else { return }
        hideTerminalKeyboard()
        isShowingTerminalPaneSheet = true
    }

    private var terminalRendererMenu: some View {
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
            .disabled(!allowsSwiftTermRenderer)
        } label: {
            terminalToolbarIcon(isSwiftTermRendererActive ? "bolt.horizontal.circle" : "shield.lefthalf.filled")
        }
    }

    private var terminalCreateButton: some View {
        Button {
            openCreateTerminalSheet()
        } label: {
            terminalToolbarIcon("plus")
        }
        .disabled(!codex.isConnected || isCreatingTerminal)
    }

    private var terminalRefreshButton: some View {
        Button {
            isSwiftTermRendererActive ? startStream(force: true) : refreshTerminals()
        } label: {
            if isStartingStream || isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
                    .adaptiveToolbarItem(in: Circle())
            } else {
                terminalToolbarIcon("arrow.clockwise")
            }
        }
        .disabled(!codex.isConnected || selectedPaneTarget == nil || isStartingStream || isRefreshing)
    }

    private func terminalToolbarIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 24, height: 24)
            .contentShape(Circle())
            .adaptiveToolbarItem(in: Circle())
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
                    fontSize: CGFloat(effectiveFontSize),
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
                    focusTerminalInput()
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
                fontSize: CGFloat(effectiveFontSize),
                backgroundColor: UIColor(theme.terminalSurface),
                foregroundColor: UIColor(theme.terminalText),
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
            fontSize: sessionFontSizeBinding,
            theme: theme,
            pinnedShortcuts: pinnedShortcuts,
            displayedActiveShortcuts: displayedActiveShortcuts,
            shortcutProfile: shortcutProfile,
            customShortcutIDs: customShortcutIDs,
            isKeyboardPresented: isKeyboardPresented,
            isControlModifierLatched: isControlModifierLatched,
            isMetaModifierLatched: isMetaModifierLatched,
            onFocusTerminalInput: { focusTerminalInput() },
            onHideTerminalKeyboard: { hideTerminalKeyboard() },
            onSendTab: { sendKeyValue(ManagedTerminalKey.tab.rawValue) },
            onSendDirectionalKey: { direction in sendKeyValue(direction.keyValue, duplicateInterval: 0.05) },
            onSendEscape: { sendKeyValue(ManagedTerminalKey.escape.rawValue) },
            onSendInterrupt: { sendKeyValue(ManagedTerminalKey.ctrlC.rawValue) },
            onToggleKeyBarExpanded: { toggleKeyBarExpanded() },
            onControlModifier: { latchControlModifier() },
            onMetaModifier: { latchMetaModifier() },
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
                openCreateTerminalSheet()
            } label: {
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
        codex.terminalPanes.filter { !SwiftTerminalPaneHeuristics.isInternalBridgePane($0) }
    }

    private var selectedPane: ManagedTerminalPane? {
        if let selectedPaneTarget,
           let pane = displayedPanes.first(where: { $0.matches(target: selectedPaneTarget) }) {
            return pane
        }
        return SwiftTerminalPaneHeuristics.preferredDefaultPane(in: displayedPanes)
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
        let sanitized = TerminalTextUtilities.trimBlankEdges(
            SwiftTerminalANSIRenderer.plainText(from: currentSnapshotText)
        )
        return sanitized.isEmpty ? " " : sanitized
    }

    private var currentSnapshotAttributedText: AttributedString {
        SwiftTerminalANSIRenderer.attributedText(
            from: currentSnapshotText,
            defaultForeground: theme.terminalText
        )
    }

    private var paneTitleForHeader: String {
        if !paneTitle.isEmpty, paneTitle != "Swift", paneTitle != "Terminal" {
            return paneTitle
        }
        return selectedPane?.displayTitle ?? LocalizationManager.shared.localized("tab.terminal")
    }

    private var terminalHeaderDetailText: String {
        if let command = terminalJoinCommandText {
            return command
        }
        return statusText
    }

    private var terminalJoinCommandText: String? {
        guard let selectedPane else { return nil }
        return "mmr join \(terminalJoinTarget(for: selectedPane))"
    }

    private var statusText: String {
        let sizeText = latestSize.map { "\($0.cols)x\($0.rows)" } ?? "--x--"
        if isSwiftTermRendererActive {
            return "\(statusLine) · \(sizeText)"
        }
        return "\(rendererMode.localizedTitle) · \(sizeText)"
    }

    private func terminalJoinTarget(for pane: ManagedTerminalPane) -> String {
        let address = pane.paneAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty, address != "unknown" {
            return address
        }

        let target = pane.requestTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.isEmpty {
            return target
        }

        return pane.sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func copySelectedPaneJoinCommand() {
        guard let selectedPane else { return }
        copyJoinCommand(for: selectedPane)
    }

    private func copyJoinCommand(for pane: ManagedTerminalPane) {
        UIPasteboard.general.string = "mmr join \(terminalJoinTarget(for: pane))"
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
            decodedCustomShortcuts() ?? [],
            SwiftTerminalShortcut.defaultPinnedShortcuts,
            SwiftTerminalShortcut.compactProfile,
            SwiftTerminalShortcut.agentProfile,
            SwiftTerminalShortcut.shellProfile,
            SwiftTerminalShortcut.macProfile,
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

    private var customShortcutIDs: Set<String> {
        Set((decodedCustomShortcuts() ?? []).map(\.id))
    }

    private var stablePollKey: String {
        "\(rendererModeRaw)|\(selectedPaneTarget ?? "-")|\(codex.isConnected)|\(scenePhase == .active)|\(terminalFontFamilyRaw)|\(useDarkTerminalCanvas)|\(effectiveFontSize)"
    }

    private var stableCanvasResetKey: String {
        "\(selectedPaneTarget ?? selectedPane?.requestTarget ?? "-")|\(terminalFontFamilyRaw)|\(useDarkTerminalCanvas)|\(colorScheme)|\(effectiveFontSize)"
    }

    private var sessionFontSizeBinding: Binding<Double> {
        Binding(
            get: { effectiveFontSize },
            set: { sessionFontSizeOverride = $0 }
        )
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

    private var swiftTerminalBorder: Color {
        theme.border
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
            let snapshot = try await codex.refreshTerminalSnapshot(
                paneId: target,
                preserveAnsi: true,
                joinWrapped: false,
                fullHistory: true
            )
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
        let requestedName = newTerminalName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = requestedName.isEmpty ? uniqueSwiftSessionName() : requestedName
        let cwd = newTerminalCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cwd.isEmpty else { return }
        Task {
            isCreatingTerminal = true
            defer { isCreatingTerminal = false }
            do {
                let list = try await codex.createManagedTerminal(
                    name: effectiveName,
                    cwd: cwd,
                    command: nil,
                    cols: latestSize?.cols,
                    rows: latestSize?.rows,
                    openVisible: createOpenVisibleOnMac,
                    visibleApp: createVisibleApp.rpcValue
                )
                newTerminalName = ""
                isShowingCreateTerminalSheet = false
                selectedPaneTarget = list.createdPane?.requestTarget ?? list.panes.first?.requestTarget
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func openCreateTerminalSheet() {
        let selectedCwd = selectedPane?.cwd.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !selectedCwd.isEmpty {
            newTerminalCwd = selectedCwd
        } else if newTerminalCwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newTerminalCwd = "/"
        }
        createOpenVisibleOnMac = openVisibleTerminalOnCreate
        createVisibleAppRaw = terminalVisibleAppRaw
        isShowingCreateTerminalSheet = true
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
                if selectedWasClosed || selectedPaneTarget == nil || !list.panes.contains(where: { $0.matches(target: selectedPaneTarget) }) {
                    selectedPaneTarget = list.panes.first?.requestTarget
                }
                await refreshStableSnapshotIfNeeded()
            } catch {
                pendingCloseRequest = nil
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func startStream(force: Bool = false) {
        guard isSwiftTermRendererActive else { return }
        guard codex.isConnected else { return }
        guard scenePhase == .active else { return }
        let pane = selectedPane
        guard let target = selectedPaneTarget ?? pane?.requestTarget else { return }
        guard let size = latestSize, size.cols > 10, size.rows > 5 else {
            statusLine = "sizing"
            return
        }
        let startSignature = "\(target)|\(size.cols)x\(size.rows)|\(scenePhase == .active)|\(codex.isConnected)"
        if !force {
            if isStartingStream && pendingStreamStartSignature == startSignature {
                return
            }
            if streamId != nil && activeStreamSignature == startSignature {
                return
            }
        }
        let previousStreamId = streamId
        streamLifecycleToken += 1
        let token = streamLifecycleToken
        pendingStreamStartSignature = startSignature
        isStartingStream = true
        startStreamTask?.cancel()
        startStreamTask = Task {
            defer {
                if token == streamLifecycleToken {
                    isStartingStream = false
                    pendingStreamStartSignature = ""
                    startStreamTask = nil
                }
            }
            do {
                if let previousStreamId {
                    try? await codex.stopTerminalStream(streamId: previousStreamId)
                    guard !Task.isCancelled, token == streamLifecycleToken else { return }
                    if streamId == previousStreamId {
                        streamId = nil
                    }
                }
                try Task.checkCancellation()
                statusLine = "connecting"
                let response = try await codex.startTerminalStream(
                    paneId: target,
                    cols: size.cols,
                    rows: size.rows,
                    replay: true,
                    replayFullHistory: true
                )
                guard !Task.isCancelled, token == streamLifecycleToken else {
                    try? await codex.stopTerminalStream(streamId: response.streamId)
                    return
                }
                streamId = response.streamId
                activeStreamSignature = startSignature
                statusLine = response.status
                lastStreamReconnectSignature = ""
            } catch is CancellationError {
                return
            } catch {
                if token == streamLifecycleToken {
                    streamId = nil
                    activeStreamSignature = ""
                    statusLine = "stream error"
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
        activeStreamSignature = ""
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
        swiftTermInputReplayTask?.cancel()
        swiftTermInputReplayTask = nil
        isStartingStream = false
        pendingStreamStartSignature = ""
        activeStreamSignature = ""
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
        let streamIdAtSend = streamId
        if isLineEndingData(data) {
            guard !shouldSuppressInput(signature: "bytes:\(target):enter", interval: 0.35) else { return }
        } else if isPasteLikeTextData(data) {
            guard !shouldSuppressInput(signature: "bytes:\(target):paste:\(data.base64EncodedString())", interval: 0.16) else { return }
        }
        clearLatchedTerminalModifiers()
        Task {
            do {
                try await codex.sendTerminalData(data, paneId: target)
                scheduleStableRefresh(target: target)
                scheduleSwiftTermInputReplay(streamIdAtSend: streamIdAtSend)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func scheduleSwiftTermInputReplay(streamIdAtSend: String?) {
        guard replaysSwiftTermAfterInput else { return }
        guard isSwiftTermRendererActive, let streamIdAtSend else { return }
        swiftTermInputReplayTask?.cancel()
        swiftTermInputReplayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled,
                  isSwiftTermRendererActive,
                  streamId == streamIdAtSend,
                  scenePhase == .active else {
                return
            }
            do {
                try await codex.replayTerminalStream(streamId: streamIdAtSend)
            } catch {
                if !Task.isCancelled {
                    statusLine = "replay error"
                }
            }
            swiftTermInputReplayTask = nil
        }
    }

    private func sendText(_ text: String) {
        guard let target = selectedPaneTarget, !text.isEmpty else { return }
        guard !shouldSuppressInput(signature: "text:\(target):\(text)", interval: 0.25) else { return }
        let streamIdAtSend = streamId
        clearLatchedTerminalModifiers()
        Task {
            do {
                if text.contains("\n") || text.contains("\r") {
                    try await codex.sendTerminalData(Data(text.utf8), paneId: target)
                } else {
                    try await codex.sendTerminalText(text, paneId: target)
                }
                scheduleStableRefresh(target: target)
                scheduleSwiftTermInputReplay(streamIdAtSend: streamIdAtSend)
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
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            keyBarExpanded.toggle()
        }
    }

    private func latchControlModifier() {
        guard isSwiftTermRendererActive else { return }
        isControlModifierLatched = true
        isMetaModifierLatched = false
        controlModifierRequestID += 1
        focusTerminalInput()
    }

    private func latchMetaModifier() {
        guard isSwiftTermRendererActive else { return }
        isMetaModifierLatched = true
        isControlModifierLatched = false
        metaModifierRequestID += 1
        focusTerminalInput()
    }

    private func clearLatchedTerminalModifiers() {
        isControlModifierLatched = false
        isMetaModifierLatched = false
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

    private func sendKeyValue(_ keyValue: String, duplicateInterval: TimeInterval? = nil) {
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
        let interval = duplicateInterval ?? (normalizedKey == ManagedTerminalKey.enter.rawValue ? 0.35 : 0.18)
        guard !shouldSuppressInput(signature: "key:\(target):\(normalizedKey)", interval: interval) else { return }
        let streamIdAtSend = streamId
        clearLatchedTerminalModifiers()
        Task {
            do {
                try await codex.sendTerminalKeyValue(normalizedKey, paneId: target)
                scheduleStableRefresh(target: target)
                scheduleSwiftTermInputReplay(streamIdAtSend: streamIdAtSend)
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

    private func focusTerminalInput(allowDuringDismissSuppression: Bool = false) {
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
        clearLatchedTerminalModifiers()
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
        clearLatchedTerminalModifiers()
        isCommandFieldFocused = false
        if isSwiftTermRendererActive {
            blurRequestID += 1
        }
        dismissActiveKeyboard()
    }

    private func suppressKeyboardForVirtualShortcut() {
        clearLatchedTerminalModifiers()
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
        let currentIndex = panes.firstIndex { $0.matches(target: selectedPaneTarget) } ?? 0
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
        let charWidth = max(5.6, effectiveFontSize * 0.60)
        let rowHeight = max(12.0, effectiveFontSize * 1.25)
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
        if swiftTermRestoreRevision < swiftTermRestoreRevisionTarget,
           stableDefaultRevision > stableFallbackRevision,
           rendererMode == .stable {
            rendererModeRaw = SwiftTerminalRendererMode.swiftTerm.rawValue
            swiftTermRestoreRevision = swiftTermRestoreRevisionTarget
        }
    }

    private func enableBracketedPasteByDefaultIfNeeded() {
        guard bracketedPasteDefaultRevision < bracketedPasteDefaultRevisionTarget else { return }
        bracketedPaste = true
        bracketedPasteDefaultRevision = bracketedPasteDefaultRevisionTarget
    }

    private func selectDefaultPaneIfNeeded(preferUsefulDefault: Bool = false) {
        let preferred = SwiftTerminalPaneHeuristics.preferredDefaultPane(in: displayedPanes)
        if let selectedPaneTarget,
           let currentPane = displayedPanes.first(where: { $0.matches(target: selectedPaneTarget) }) {
            if preferUsefulDefault,
               let preferred,
               !preferred.matches(target: selectedPaneTarget),
               SwiftTerminalPaneHeuristics.defaultScore(preferred) >= SwiftTerminalPaneHeuristics.defaultScore(currentPane) + 200 {
                self.selectedPaneTarget = preferred.requestTarget
            }
            return
        }
        selectedPaneTarget = preferred?.requestTarget
    }

    private func uniqueSwiftSessionName() -> String {
        "terminal-\(Int(Date().timeIntervalSince1970))"
    }


}

private struct SwiftTerminalPanePickerSheet: View {
    let panes: [ManagedTerminalPane]
    let selectedPaneTarget: String?
    let isConnected: Bool
    let isRefreshing: Bool
    let isCreatingTerminal: Bool
    let theme: SwiftTerminalTheme
    let onSelectPane: (ManagedTerminalPane) -> Void
    let onCreate: () -> Void
    let onRefresh: () -> Void
    let onCopyJoin: (ManagedTerminalPane) -> Void
    let onCopyAddress: (ManagedTerminalPane) -> Void
    let onClosePane: (ManagedTerminalPane) -> Void
    let onCloseSession: (ManagedTerminalPane) -> Void
    let onOpenSettings: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.border)
            searchField
            actionRow
            paneList
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            ZStack {
                Rectangle().fill(Color(.secondarySystemGroupedBackground))
                LinearGradient(
                    colors: [
                        terminalSheetAccent.opacity(theme.isDark ? 0.16 : 0.10),
                        Color(red: 0.02, green: 0.06, blue: 0.10).opacity(theme.isDark ? 0.22 : 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(.secondarySystemGroupedBackground))
    }

    private var terminalSheetAccent: Color {
        Color(red: 0.38, green: 0.82, blue: 1.00)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(terminalSheetAccent)
                .frame(width: 38, height: 38)
                .background(terminalSheetAccent.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizationManager.shared.localized("swift_terminal.sidebar.title"))
                    .font(AppFont.title3(weight: .semibold))
                    .foregroundStyle(theme.primaryText)
                    .lineLimit(1)
                Text(String(format: LocalizationManager.shared.localized("swift_terminal.sidebar.count"), panes.count))
                    .font(AppFont.caption())
                    .foregroundStyle(theme.secondaryText)
            }

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 32, height: 32)
                    .background(theme.buttonBackground, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LocalizationManager.shared.localized("sidebar.close_menu"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 30)
        .padding(.bottom, 14)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText)

            TextField(LocalizationManager.shared.localized("swift_terminal.sidebar.search"), text: $searchText)
                .font(AppFont.body())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(theme.buttonBackground.opacity(theme.isDark ? 0.72 : 0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: onCreate) {
                Label(LocalizationManager.shared.localized("swift_terminal.create"), systemImage: "plus")
                    .font(AppFont.caption(weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
            }
            .disabled(!isConnected || isCreatingTerminal)

            Button(action: onRefresh) {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                } else {
                    Label(LocalizationManager.shared.localized("terminal.accessibility.refresh"), systemImage: "arrow.clockwise")
                        .font(AppFont.caption(weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
            }
            .disabled(!isConnected || isRefreshing)
        }
        .buttonStyle(.bordered)
        .tint(terminalSheetAccent)
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var paneList: some View {
        if filteredPanes.isEmpty {
            emptyState
        } else {
            List {
                ForEach(groupedPanes) { group in
                    Section {
                        ForEach(group.panes) { pane in
                            SwiftTerminalPanePickerRow(
                                pane: pane,
                                isSelected: pane.matches(target: selectedPaneTarget),
                                theme: theme,
                                accent: terminalSheetAccent,
                                joinCommand: joinCommand(for: pane),
                                path: displayPath(for: pane),
                                onSelect: { onSelectPane(pane) },
                                onCopyJoin: { onCopyJoin(pane) },
                                onCopyAddress: { onCopyAddress(pane) },
                                onClosePane: { onClosePane(pane) },
                                onCloseSession: { onCloseSession(pane) }
                            )
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 10, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    onCopyJoin(pane)
                                } label: {
                                    Label(LocalizationManager.shared.localized("terminal.context.copy_join"), systemImage: "doc.on.doc")
                                }
                                .tint(terminalSheetAccent)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    onClosePane(pane)
                                } label: {
                                    Label(LocalizationManager.shared.localized("terminal.context.close"), systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text(group.title)
                            .font(AppFont.caption2(weight: .semibold))
                            .foregroundStyle(theme.secondaryText)
                            .textCase(.uppercase)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let onOpenSettings {
                SidebarFloatingSettingsButton(colorScheme: colorScheme, action: onOpenSettings)
            }
            Spacer(minLength: 0)
            Text(LocalizationManager.shared.localized(isConnected ? "connection.connected" : "connection.offline"))
                .font(AppFont.mono(.subheadline))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(terminalSheetAccent)
            Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                 ? LocalizationManager.shared.localized("swift_terminal.no_pane")
                 : LocalizationManager.shared.localized("swift_terminal.sidebar.no_match"))
                .font(AppFont.callout(weight: .semibold))
                .foregroundStyle(theme.primaryText)
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(LocalizationManager.shared.localized("swift_terminal.sidebar.empty_hint"))
                    .font(AppFont.caption())
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var filteredPanes: [ManagedTerminalPane] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return panes }
        return panes.filter { pane in
            pane.displayTitle.localizedCaseInsensitiveContains(query)
                || pane.sessionName.localizedCaseInsensitiveContains(query)
                || pane.cwd.localizedCaseInsensitiveContains(query)
                || joinCommand(for: pane).localizedCaseInsensitiveContains(query)
        }
    }

    private var groupedPanes: [SwiftTerminalPanePickerGroup] {
        var orderedSessions: [String] = []
        var buckets: [String: [ManagedTerminalPane]] = [:]
        for pane in filteredPanes {
            let title = sessionTitle(for: pane)
            if buckets[title] == nil {
                orderedSessions.append(title)
                buckets[title] = []
            }
            buckets[title]?.append(pane)
        }

        return orderedSessions.map { title in
            SwiftTerminalPanePickerGroup(
                title: title,
                panes: (buckets[title] ?? []).sorted { lhs, rhs in
                    if lhs.windowIndex != rhs.windowIndex {
                        return lhs.windowIndex < rhs.windowIndex
                    }
                    return lhs.paneIndex < rhs.paneIndex
                }
            )
        }
    }

    private func sessionTitle(for pane: ManagedTerminalPane) -> String {
        let session = pane.sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        return session.isEmpty ? LocalizationManager.shared.localized("tab.terminal") : session
    }

    private func joinCommand(for pane: ManagedTerminalPane) -> String {
        "mmr join \(joinTarget(for: pane))"
    }

    private func joinTarget(for pane: ManagedTerminalPane) -> String {
        let address = pane.paneAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        if !address.isEmpty, address != "unknown" {
            return address
        }

        let target = pane.requestTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        if !target.isEmpty {
            return target
        }

        return pane.sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func displayPath(for pane: ManagedTerminalPane) -> String {
        let cwd = pane.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cwd.isEmpty else { return pane.paneAddress }
        let home = NSHomeDirectory()
        if cwd == home {
            return "~"
        }
        if cwd.hasPrefix(home + "/") {
            return "~/" + cwd.dropFirst(home.count + 1)
        }
        return cwd
    }
}

private struct SwiftTerminalPanePickerGroup: Identifiable {
    let title: String
    let panes: [ManagedTerminalPane]

    var id: String { title }
}

private struct SwiftTerminalPanePickerRow: View {
    let pane: ManagedTerminalPane
    let isSelected: Bool
    let theme: SwiftTerminalTheme
    let accent: Color
    let joinCommand: String
    let path: String
    let onSelect: () -> Void
    let onCopyJoin: () -> Void
    let onCopyAddress: () -> Void
    let onClosePane: () -> Void
    let onCloseSession: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 11) {
                statusIcon
                VStack(alignment: .leading, spacing: 6) {
                    titleLine
                    metadataLine
                    joinLine
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.62) : theme.border, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: onCopyJoin) {
                Label(LocalizationManager.shared.localized("terminal.context.copy_join"), systemImage: "terminal")
            }
            Button(action: onCopyAddress) {
                Label(LocalizationManager.shared.localized("terminal.context.copy_address"), systemImage: "number")
            }
            Divider()
            Button(role: .destructive, action: onClosePane) {
                Label(LocalizationManager.shared.localized("terminal.context.close"), systemImage: "xmark.circle")
            }
            if !pane.sessionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button(role: .destructive, action: onCloseSession) {
                    Label(LocalizationManager.shared.localized("terminal.context.close_session"), systemImage: "rectangle.stack.badge.minus")
                }
            }
        }
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(isSelected ? accent : theme.buttonBackground)
            Image(systemName: pane.active ? "play.fill" : "terminal")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(isSelected ? theme.selectedChipText : theme.secondaryText)
        }
        .frame(width: 28, height: 28)
    }

    private var titleLine: some View {
        HStack(spacing: 6) {
            Text(pane.displayTitle)
                .font(AppFont.callout(weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
            if isSelected {
                Text(LocalizationManager.shared.localized("swift_terminal.sidebar.current"))
                    .font(AppFont.caption2(weight: .bold))
                    .foregroundStyle(theme.selectedChipText)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accent, in: Capsule())
            }
        }
    }

    private var metadataLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
            Text(path)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(AppFont.caption2())
        .foregroundStyle(theme.secondaryText)
    }

    private var joinLine: some View {
        Text(joinCommand)
            .font(AppFont.mono(.caption2))
            .foregroundStyle(accent.opacity(0.9))
            .lineLimit(2)
            .textSelection(.enabled)
            .truncationMode(.middle)
    }

    private var rowBackground: Color {
        isSelected
            ? accent.opacity(theme.isDark ? 0.18 : 0.13)
            : theme.buttonBackground.opacity(theme.isDark ? 0.55 : 0.72)
    }
}

private struct SwiftTerminalCreateSheet: View {
    @Binding var name: String
    @Binding var cwd: String
    @Binding var openVisibleOnMac: Bool
    @Binding var visibleAppRaw: String

    let isCreating: Bool
    let onCreate: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingFolderBrowser = false

    private var visibleAppBinding: Binding<TerminalVisibleAppPreference> {
        Binding(
            get: { TerminalVisibleAppPreference(rawValue: visibleAppRaw) ?? .auto },
            set: { visibleAppRaw = $0.rawValue }
        )
    }

    private var canCreate: Bool {
        !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCreating
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(LocalizationManager.shared.localized("terminal.new_terminal")) {
                    TextField(LocalizationManager.shared.localized("terminal.placeholder.name"), text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section(LocalizationManager.shared.localized("folder.section.current")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "/" : cwd)
                            .font(AppFont.mono(.footnote))
                            .textSelection(.enabled)
                            .lineLimit(3)
                            .truncationMode(.middle)

                        Button {
                            isShowingFolderBrowser = true
                        } label: {
                            Label(LocalizationManager.shared.localized("picker.add_local"), systemImage: "folder")
                        }
                    }
                    .padding(.vertical, 2)
                }

                Section {
                    Toggle(LocalizationManager.shared.localized("terminal.toggle.open_mac_app"), isOn: $openVisibleOnMac)
                    if openVisibleOnMac {
                        Picker(LocalizationManager.shared.localized("terminal.settings.visible_app"), selection: visibleAppBinding) {
                            ForEach(TerminalVisibleAppPreference.allCases) { app in
                                Text(app.localizedTitle).tag(app)
                            }
                        }
                    }
                }
            }
            .navigationTitle(LocalizationManager.shared.localized("terminal.new_terminal"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizationManager.shared.localized("common.cancel")) {
                        dismiss()
                    }
                    .disabled(isCreating)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onCreate()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Text(LocalizationManager.shared.localized("terminal.button.create"))
                        }
                    }
                    .disabled(!canCreate)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $isShowingFolderBrowser) {
            SidebarLocalFolderBrowserSheet { projectPath in
                cwd = projectPath
                isShowingFolderBrowser = false
            }
        }
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
