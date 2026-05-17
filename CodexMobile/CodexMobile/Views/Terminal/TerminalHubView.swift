// FILE: TerminalHubView.swift
// Purpose: Managed terminal mode UI for listing panes, rendering SwiftTerm snapshots, and sending input.
// Layer: View
// Exports: TerminalHubView
// Depends on: SwiftUI, UIKit, CodexService, TerminalModels, AppFont

import SwiftUI
import UIKit

struct TerminalHubView: View {
    @Environment(CodexService.self) private var codex

    let onClose: (() -> Void)?

    @AppStorage("terminal.experimentalSwiftTermRenderer") private var useExperimentalSwiftTermRenderer = false
    @AppStorage(TerminalFontFamily.storageKey) private var terminalFontFamilyRaw = TerminalFontFamily.defaultStoredRawValue
    @AppStorage(TerminalVisibleAppPreference.storageKey) private var terminalVisibleAppRaw = TerminalVisibleAppPreference.defaultStoredRawValue
    @State private var commandDraft = ""
    @State private var newTerminalName = ""
    @State private var newTerminalCwd = "/"
    @State private var newTerminalCommand = ""
    @State private var openVisibleTerminalOnMac = false
    @State private var isRefreshing = false
    @State private var isSendingInput = false
    @State private var isCreatingTerminal = false
    @State private var isOpeningVisibleTerminal = false
    @State private var isClosingTerminal = false
    @State private var isShowingCreateTerminalSheet = false
    @State private var panePendingClose: ManagedTerminalPane?
    @State private var localErrorMessage: String?
    @State private var visibleTerminalPanes: [ManagedTerminalPane] = []
    @State private var localSelectedTerminalPaneTarget: String?
    @State private var terminalDebugLine = "Terminal list not loaded yet."
    @State private var pendingTerminalInputRefreshTask: Task<Void, Never>?
    @State private var terminalFocusRequestID = 0
    @State private var terminalCopyRequestID = 0
    @State private var terminalPasteRequestID = 0
    @State private var terminalControlModifierRequestID = 0
    @State private var terminalMetaModifierRequestID = 0
    @State private var lastStableViewportSignature = ""
    @FocusState private var isCommandFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if !codex.isConnected {
                terminalOfflineBanner
            }

            if displayedTerminalPanes.isEmpty && !codex.isLoadingTerminals {
                emptyState
            } else {
                terminalContent
            }
        }
        .navigationTitle(LocalizationManager.shared.localized("tab.terminal"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button(LocalizationManager.shared.localized("terminal.toolbar.chats"), action: onClose)
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    openCreateTerminalSheet()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!codex.isConnected || isCreatingTerminal)
                .accessibilityLabel(LocalizationManager.shared.localized("terminal.accessibility.new_terminal"))

                Button(role: .destructive) {
                    panePendingClose = selectedVisiblePane
                } label: {
                    if isClosingTerminal {
                        ProgressView()
                    } else {
                        Image(systemName: "xmark.circle")
                    }
                }
                .disabled(!codex.isConnected || selectedVisiblePane == nil || isClosingTerminal)
                .accessibilityLabel(LocalizationManager.shared.localized("terminal.accessibility.close_terminal"))

                Button {
                    openSelectedPaneOnMac()
                } label: {
                    if isOpeningVisibleTerminal {
                        ProgressView()
                    } else {
                        Image(systemName: "display")
                    }
                }
                .disabled(!codex.isConnected || selectedVisiblePane == nil || isOpeningVisibleTerminal)
                .accessibilityLabel(LocalizationManager.shared.localized("terminal.accessibility.open_on_mac"))

                Button {
                    refreshTerminals()
                } label: {
                    if isRefreshing || codex.isLoadingTerminals {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(!codex.isConnected || isRefreshing || codex.isLoadingTerminals)
                .accessibilityLabel(LocalizationManager.shared.localized("terminal.accessibility.refresh"))
            }
        }
        .task {
            if codex.isConnected {
                await refreshTerminalsAsync(presentsErrors: false, source: "initial")
            }
        }
        .task(id: codex.isConnected) {
            await pollTerminalList()
        }
        .task(id: selectedVisiblePaneTarget) {
            await pollSelectedPaneSnapshot(paneId: selectedVisiblePaneTarget)
        }
        .alert(LocalizationManager.shared.localized("terminal.alert.error_title"), isPresented: terminalErrorIsPresented) {
            Button(LocalizationManager.shared.localized("common.ok"), role: .cancel) {
                localErrorMessage = nil
                codex.terminalLastErrorMessage = nil
            }
        } message: {
            Text(localErrorMessage ?? codex.terminalLastErrorMessage ?? LocalizationManager.shared.localized("terminal.alert.error_message"))
        }
        .confirmationDialog(
            LocalizationManager.shared.localized("terminal.dialog.close_title"),
            isPresented: closeDialogIsPresented,
            titleVisibility: .visible
        ) {
            if let pane = panePendingClose {
                Button(String(format: LocalizationManager.shared.localized("terminal.close_pane"), pane.displayTitle), role: .destructive) {
                    closePane(pane)
                }
            }
            Button(LocalizationManager.shared.localized("sidebar.cancel"), role: .cancel) {}
        } message: {
            Text(String(format: LocalizationManager.shared.localized("terminal.dialog.close_message"), panePendingClose?.paneKey ?? ""))
        }
        .sheet(isPresented: $isShowingCreateTerminalSheet) {
            NavigationStack {
                ScrollView {
                    createTerminalCard
                        .padding(20)
                }
                .navigationTitle(LocalizationManager.shared.localized("terminal.new_terminal"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(LocalizationManager.shared.localized("sidebar.cancel")) {
                            isShowingCreateTerminalSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var terminalContent: some View {
        VStack(spacing: 0) {
            paneStrip
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))

            Divider()

            terminalSnapshotView

            Divider()

            terminalControlsBar
                .padding(12)
                .background(Color(.systemBackground))
        }
    }

    private var paneStrip: some View {
        HStack(spacing: 10) {
            if let pane = selectedVisiblePane {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pane.displayTitle)
                        .font(AppFont.subheadline(weight: .semibold))
                        .lineLimit(1)
                    Text(pane.paneKey)
                        .font(AppFont.mono(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .contextMenu {
                    paneContextMenu(for: pane)
                }
            } else {
                Text(LocalizationManager.shared.localized("terminal.status.no_pane"))
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Menu {
                ForEach(displayedTerminalPanes) { pane in
                    Button {
                        attachPane(pane)
                    } label: {
                        Label(pane.displayTitle, systemImage: isSelected(pane) ? "checkmark.circle.fill" : "terminal")
                    }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Color(.systemBackground), in: Circle())
            }
            .disabled(displayedTerminalPanes.isEmpty)
        }
    }

    private var terminalSnapshotView: some View {
        Group {
            if isSwiftTermRendererActive {
                SwiftTermTerminalView(
                    paneTarget: selectedVisiblePaneTarget,
                    snapshotText: currentSnapshotText,
                    isConnected: codex.isConnected,
                    focusRequestID: terminalFocusRequestID,
                    copyRequestID: terminalCopyRequestID,
                    pasteRequestID: terminalPasteRequestID,
                    controlModifierRequestID: terminalControlModifierRequestID,
                    metaModifierRequestID: terminalMetaModifierRequestID,
                    onSendData: sendTerminalData,
                    onResize: resizeTerminalFromRenderer
                )
                .background(Color(red: 0.025, green: 0.027, blue: 0.032))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { focusTerminal() })
            } else {
                stableSnapshotTextView
            }
        }
    }

    private var stableSnapshotTextView: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(currentSnapshotDisplayText)
                            .font(AppFont.terminalMono(.caption))
                            .foregroundStyle(Color(.label))
                            .lineSpacing(1)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        Color.clear
                            .frame(height: 1)
                            .id("terminal-bottom")
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                }
                .background(Color(.systemBackground))
                .contentShape(Rectangle())
                .onTapGesture {
                    isCommandFieldFocused = true
                }
                .onAppear {
                    resizeStableTerminalIfNeeded(size: geometry.size)
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
                .onChange(of: geometry.size) { _, newSize in
                    resizeStableTerminalIfNeeded(size: newSize)
                }
                .onChange(of: currentSnapshotText) { _, _ in
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var terminalControlsBar: some View {
        VStack(spacing: 10) {
            if isSwiftTermRendererActive {
                swiftTermInputControls
            } else {
                stableCommandInputBar
            }

            LazyVGrid(columns: quickKeyColumns, spacing: 8) {
                if isSwiftTermRendererActive {
                    terminalActionButton(LocalizationManager.shared.localized("terminal.button.ctrl")) {
                        requestControlModifier()
                    }
                    terminalActionButton(LocalizationManager.shared.localized("terminal.button.alt")) {
                        requestMetaModifier()
                    }
                    terminalActionButton(LocalizationManager.shared.localized("terminal.button.cmd_c")) {
                        copyTerminalSelection()
                    }
                    terminalActionButton(LocalizationManager.shared.localized("terminal.button.cmd_v")) {
                        pasteClipboardIntoTerminal()
                    }
                }
                ForEach(quickKeys) { key in
                    Button(key.label) {
                        sendKey(key)
                    }
                    .font(AppFont.caption(weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                    .buttonStyle(.plain)
                    .disabled(!canSendInput)
                }
            }
        }
    }

    private var swiftTermInputControls: some View {
        HStack(spacing: 8) {
            liveStatusBadge

            Button {
                focusTerminal()
            } label: {
                Label(LocalizationManager.shared.localized("terminal.keyboard"), systemImage: "keyboard")
                    .font(AppFont.caption2(weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .disabled(!canSendInput)

            Spacer(minLength: 8)

            Button {
                copyTerminalSelection()
            } label: {
                Label(LocalizationManager.shared.localized("terminal.button.copy"), systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .disabled(!canSendInput)

            Button {
                pasteClipboardIntoTerminal()
            } label: {
                Label(LocalizationManager.shared.localized("terminal.button.paste"), systemImage: "doc.on.clipboard")
                    .labelStyle(.iconOnly)
            }
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .disabled(!canSendInput)
        }
    }

    private var stableCommandInputBar: some View {
        HStack(spacing: 10) {
            liveStatusBadge

            TextField(LocalizationManager.shared.localized("terminal.placeholder.command"), text: $commandDraft, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppFont.mono(.body))
                .lineLimit(1...3)
                .focused($isCommandFieldFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .submitLabel(.send)
                .onSubmit { sendCommandFromDraft() }

            Button {
                sendCommandFromDraft()
            } label: {
                if isSendingInput {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.fill")
                }
            }
            .frame(width: 44, height: 44)
            .foregroundStyle(Color(.systemBackground))
            .background(Color.primary, in: Circle())
            .buttonStyle(.plain)
            .disabled(!canSendInput || commandDraft.isEmpty)
        }
    }

    private var liveStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(codex.selectedTerminalPane == nil ? Color(.tertiaryLabel) : .green)
                .frame(width: 6, height: 6)
            Text(codex.selectedTerminalPane == nil ? LocalizationManager.shared.localized("terminal.status.no_pane") : LocalizationManager.shared.localized("terminal.status.live"))
                .font(AppFont.caption2(weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(Color(.secondarySystemBackground), in: Capsule())
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(LocalizationManager.shared.localized("terminal.no_managed"))
                .font(AppFont.title3(weight: .semibold))
            Text(LocalizationManager.shared.localized("terminal.create_hint"))
                .font(AppFont.callout())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Text(terminalDebugLine)
                .font(AppFont.mono(.caption2))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 340)
            createTerminalCard
                .frame(maxWidth: 380)
            Spacer()
        }
        .padding(24)
    }

    private var createTerminalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized: "terminal.new_terminal")
                .font(AppFont.subheadline(weight: .semibold))
            TextField(LocalizationManager.shared.localized("terminal.placeholder.name"), text: $newTerminalName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField(LocalizationManager.shared.localized("terminal.placeholder.cwd"), text: $newTerminalCwd)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField(LocalizationManager.shared.localized("terminal.placeholder.command_optional"), text: $newTerminalCommand)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Toggle(LocalizationManager.shared.localized("terminal.toggle.open_mac_app"), isOn: $openVisibleTerminalOnMac)
                .font(AppFont.callout())
            Button {
                createTerminal()
            } label: {
                HStack {
                    if isCreatingTerminal { ProgressView() }
                    Text(localized: "terminal.button.create")
                        .font(AppFont.body(weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!codex.isConnected || isCreatingTerminal || newTerminalCwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var terminalOfflineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text(localized: "terminal.offline_banner")
                .font(AppFont.caption(weight: .medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(.tertiarySystemFill))
    }

    private var currentSnapshot: ManagedTerminalSnapshot? {
        if let target = selectedVisiblePaneTarget,
           let snapshot = codex.terminalSnapshotsByPaneId[target] {
            return snapshot
        }
        guard let pane = selectedVisiblePane else { return nil }
        return codex.terminalSnapshotsByPaneId[pane.requestTarget]
            ?? codex.terminalSnapshotsByPaneId[pane.paneId]
            ?? codex.terminalSnapshotsByPaneId[pane.paneKey]
            ?? codex.terminalSnapshotsByPaneId[pane.paneAddress]
    }

    private var currentSnapshotText: String {
        if currentSnapshot?.content.isEmpty == false {
            return currentSnapshot?.content ?? ""
        }
        return selectedVisiblePane == nil
            ? LocalizationManager.shared.localized("terminal.snapshot.select_hint")
            : LocalizationManager.shared.localized("terminal.snapshot.loading")
    }

    private var currentSnapshotDisplayText: String {
        TerminalTextUtilities.trimBlankEdges(
            TerminalTextUtilities.sanitizeDisplayText(currentSnapshotText)
        )
    }

    private var canSendInput: Bool {
        codex.isConnected && selectedVisiblePaneTarget != nil && !isSendingInput
    }

    private var terminalVisibleApp: TerminalVisibleAppPreference {
        TerminalVisibleAppPreference(rawValue: terminalVisibleAppRaw) ?? .auto
    }

    private var displayedTerminalPanes: [ManagedTerminalPane] {
        codex.terminalPanes.isEmpty ? visibleTerminalPanes : codex.terminalPanes
    }

    private var selectedVisiblePane: ManagedTerminalPane? {
        if let target = localSelectedTerminalPaneTarget,
           let pane = displayedTerminalPanes.first(where: { $0.matches(target: target) }) {
            return pane
        }
        if let pane = codex.selectedTerminalPane,
           let target = paneRequestTarget(pane),
           displayedTerminalPanes.contains(where: { $0.matches(target: target) }) {
            return pane
        }
        return displayedTerminalPanes.first
    }

    private var selectedVisiblePaneTarget: String? {
        selectedVisiblePane.flatMap(paneRequestTarget)
    }

    private var quickKeys: [ManagedTerminalKey] {
        [
            .escape,
            .tab,
            .enter,
            .backspace,
            .ctrlC,
            .ctrlD,
            .ctrlZ,
            .up,
            .down,
            .left,
            .right,
        ]
    }

    private var quickKeyColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 58), spacing: 8)]
    }

    private var isSwiftTermRendererActive: Bool {
        false && useExperimentalSwiftTermRenderer
    }

    private var terminalErrorIsPresented: Binding<Bool> {
        Binding(
            get: { localErrorMessage != nil || codex.terminalLastErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    localErrorMessage = nil
                    codex.terminalLastErrorMessage = nil
                }
            }
        )
    }

    private var closeDialogIsPresented: Binding<Bool> {
        Binding(
            get: { panePendingClose != nil },
            set: { isPresented in
                if !isPresented {
                    panePendingClose = nil
                }
            }
        )
    }

    private func terminalActionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(AppFont.caption(weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 34)
            .background(Color(.secondarySystemBackground), in: Capsule())
            .buttonStyle(.plain)
            .disabled(!canSendInput)
    }

    @ViewBuilder
    private func paneContextMenu(for pane: ManagedTerminalPane) -> some View {
        Button {
            copyJoinCommand(for: pane)
        } label: {
            Label(LocalizationManager.shared.localized("terminal.context.copy_join"), systemImage: "terminal")
        }

        Button {
            copyPaneAddress(for: pane)
        } label: {
            Label(LocalizationManager.shared.localized("terminal.context.copy_address"), systemImage: "number")
        }

        Button {
            openVisiblePaneOnMac(pane)
        } label: {
            Label(LocalizationManager.shared.localized("terminal.context.open_mac"), systemImage: "display")
        }

        Button(role: .destructive) {
            panePendingClose = pane
        } label: {
            Label(LocalizationManager.shared.localized("terminal.context.close"), systemImage: "xmark.circle")
        }
    }

    private func paneChipBackground(for pane: ManagedTerminalPane) -> Color {
        isSelected(pane) ? Color.primary.opacity(0.12) : Color(.systemBackground)
    }

    private func paneChipBorder(for pane: ManagedTerminalPane) -> Color {
        isSelected(pane) ? Color.primary.opacity(0.45) : Color.primary.opacity(0.08)
    }

    private func isSelected(_ pane: ManagedTerminalPane) -> Bool {
        if let selectedPane = selectedVisiblePane {
            return paneRequestTarget(selectedPane) == paneRequestTarget(pane)
                || selectedPane.paneAddress == pane.paneAddress
        }
        return false
    }


    private func refreshTerminals() {
        Task { await refreshTerminalsAsync(presentsErrors: true, source: "manual") }
    }

    @MainActor
    private func refreshTerminalsAsync(presentsErrors: Bool, source: String) async {
        guard codex.isConnected else { return }
        isRefreshing = true
        terminalDebugLine = "Refreshing terminal/list..."
        defer { isRefreshing = false }
        do {
            let list = try await codex.refreshTerminalList(recordError: presentsErrors)
            rememberTerminalList(list, source: source)
            if let target = selectedVisiblePaneTarget {
                do {
                    try await refreshPaneSnapshot(paneId: target)
                } catch {
                    terminalDebugLine = "terminal/snapshot failed target=\(target): \(error.localizedDescription)"
                    codex.terminalLastErrorMessage = nil
                }
            }
        } catch {
            terminalDebugLine = "terminal/list failed: \(error.localizedDescription)"
            if presentsErrors {
                localErrorMessage = error.localizedDescription
            } else {
                codex.terminalLastErrorMessage = nil
            }
        }
    }

    @MainActor
    private func pollTerminalList() async {
        while !Task.isCancelled {
            guard codex.isConnected else { return }
            do {
                let list = try await codex.refreshTerminalList(showLoading: false, recordError: false)
                rememberTerminalList(list, source: "poll")
            } catch {
                if !Task.isCancelled {
                    terminalDebugLine = "terminal/list failed: \(error.localizedDescription)"
                    codex.terminalLastErrorMessage = nil
                }
                return
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    @MainActor
    private func pollSelectedPaneSnapshot(paneId: String?) async {
        guard let paneId, !paneId.isEmpty else { return }
        while !Task.isCancelled {
            guard codex.isConnected, selectedVisiblePaneTarget == paneId else { return }
            do {
                try await refreshPaneSnapshot(paneId: paneId)
            } catch {
                if !Task.isCancelled {
                    terminalDebugLine = "terminal/snapshot failed target=\(paneId): \(error.localizedDescription)"
                    codex.terminalLastErrorMessage = nil
                }
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func attachPane(_ pane: ManagedTerminalPane) {
        Task {
            do {
                localErrorMessage = nil
                codex.terminalLastErrorMessage = nil
                guard let target = paneRequestTarget(pane) else {
                    localErrorMessage = "Terminal pane target is missing. Refresh terminals and try again."
                    return
                }
                localSelectedTerminalPaneTarget = target
                try await codex.attachTerminalPane(target)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func sendEnterFromInput() {
        Task {
            isSendingInput = true
            defer { isSendingInput = false }
            do {
                let target = selectedVisiblePaneTarget
                try await codex.sendTerminalKey(.enter, paneId: target)
                scheduleTerminalInputRefresh(target: target)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func sendCommandFromDraft() {
        let command = commandDraft
        guard !command.isEmpty else { return }
        commandDraft = ""
        Task {
            isSendingInput = true
            defer { isSendingInput = false }
            do {
                let target = selectedVisiblePaneTarget
                try await codex.sendTerminalText(command, paneId: target)
                try await codex.sendTerminalKey(.enter, paneId: target)
                scheduleTerminalInputRefresh(target: target)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func sendKey(_ key: ManagedTerminalKey) {
        if isSwiftTermRendererActive {
            focusTerminal()
        }
        if !isSwiftTermRendererActive {
            if key == .enter, !commandDraft.isEmpty {
                sendCommandFromDraft()
                return
            }
            if key == .backspace, !commandDraft.isEmpty {
                commandDraft.removeLast()
                return
            }
            if key == .tab, !commandDraft.isEmpty {
                flushDraftThenSendKey(.tab)
                return
            }
        }
        Task {
            do {
                let target = selectedVisiblePaneTarget
                try await codex.sendTerminalKey(key, paneId: target)
                scheduleTerminalInputRefresh(target: target)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func flushDraftThenSendKey(_ key: ManagedTerminalKey) {
        let draft = commandDraft
        commandDraft = ""
        Task {
            isSendingInput = true
            defer { isSendingInput = false }
            do {
                let target = selectedVisiblePaneTarget
                if !draft.isEmpty {
                    try await codex.sendTerminalText(draft, paneId: target)
                }
                try await codex.sendTerminalKey(key, paneId: target)
                scheduleTerminalInputRefresh(target: target)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func sendTerminalData(_ data: Data) {
        guard !data.isEmpty else { return }
        let target = selectedVisiblePaneTarget
        Task {
            do {
                try await codex.sendTerminalData(data, paneId: target)
                scheduleTerminalInputRefresh(target: target)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func pasteClipboardIntoTerminal() {
        if isSwiftTermRendererActive {
            terminalPasteRequestID += 1
        } else if let text = UIPasteboard.general.string, !text.isEmpty {
            commandDraft += text
        }
    }

    private func copyTerminalSelection() {
        if isSwiftTermRendererActive {
            terminalCopyRequestID += 1
        } else {
            UIPasteboard.general.string = currentSnapshotDisplayText
        }
    }

    private func requestControlModifier() {
        guard isSwiftTermRendererActive else { return }
        terminalControlModifierRequestID += 1
    }

    private func requestMetaModifier() {
        guard isSwiftTermRendererActive else { return }
        terminalMetaModifierRequestID += 1
    }

    private func focusTerminal() {
        terminalFocusRequestID += 1
    }

    @discardableResult
    private func refreshPaneSnapshot(paneId: String?) async throws -> ManagedTerminalSnapshot {
        try await codex.refreshTerminalSnapshot(
            paneId: paneId,
            preserveAnsi: isSwiftTermRendererActive,
            joinWrapped: false,
            viewportOnly: true
        )
    }

    @MainActor
    private func scheduleTerminalInputRefresh(target: String?) {
        pendingTerminalInputRefreshTask?.cancel()
        pendingTerminalInputRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            _ = try? await refreshPaneSnapshot(paneId: target)
        }
    }

    private func resizeTerminalFromRenderer(cols: Int, rows: Int) {
        guard cols > 0, rows > 0 else { return }
        let target = selectedVisiblePaneTarget
        Task {
            do {
                try await codex.resizeTerminalPane(paneId: target, cols: cols, rows: rows)
                scheduleTerminalInputRefresh(target: target)
            } catch {
                terminalDebugLine = "terminal/resize failed cols=\(cols) rows=\(rows): \(error.localizedDescription)"
            }
        }
    }

    private func resizeStableTerminalIfNeeded(size: CGSize) {
        guard !isSwiftTermRendererActive, let target = selectedVisiblePaneTarget else { return }
        let dimensions = stableTerminalDimensions(for: size)
        let signature = "\(target):\(dimensions.cols)x\(dimensions.rows)"
        guard signature != lastStableViewportSignature else { return }
        lastStableViewportSignature = signature
        Task {
            do {
                try await codex.resizeTerminalPane(paneId: target, cols: dimensions.cols, rows: dimensions.rows)
                scheduleTerminalInputRefresh(target: target)
            } catch {
                terminalDebugLine = "terminal/stable-resize failed cols=\(dimensions.cols) rows=\(dimensions.rows): \(error.localizedDescription)"
            }
        }
    }

    private func openSelectedPaneOnMac() {
        guard let pane = selectedVisiblePane else { return }
        openVisiblePaneOnMac(pane)
    }

    private func openVisiblePaneOnMac(_ pane: ManagedTerminalPane) {
        Task {
            isOpeningVisibleTerminal = true
            defer { isOpeningVisibleTerminal = false }
            do {
                try await codex.openVisibleTerminalPane(
                    paneRequestTarget(pane),
                    visibleApp: terminalVisibleApp.rpcValue
                )
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func copyJoinCommand(for pane: ManagedTerminalPane) {
        UIPasteboard.general.string = "mmr join \(pane.paneAddress)"
    }

    private func copyPaneAddress(for pane: ManagedTerminalPane) {
        UIPasteboard.general.string = pane.paneAddress
    }

    private func openCreateTerminalSheet() {
        if let cwd = codex.selectedTerminalPane?.cwd, !cwd.isEmpty, newTerminalCwd == "/" {
            newTerminalCwd = cwd
        }
        isShowingCreateTerminalSheet = true
    }

    private func closePane(_ pane: ManagedTerminalPane) {
        Task {
            isClosingTerminal = true
            defer { isClosingTerminal = false }
            do {
                try await codex.killTerminalPane(paneRequestTarget(pane))
                try? await Task.sleep(nanoseconds: 200_000_000)
                let list = try await codex.refreshTerminalList(showLoading: false)
                rememberTerminalList(list, source: "close")
                if let nextTarget = selectedVisiblePaneTarget {
                    try await codex.attachTerminalPane(nextTarget)
                }
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func generatedTerminalName() -> String {
        "mms-\(Int(Date().timeIntervalSince1970))"
    }

    private func createTerminal() {
        let cwd = newTerminalCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cwd.isEmpty else { return }
        Task {
            isCreatingTerminal = true
            defer { isCreatingTerminal = false }
            do {
                let requestedName = newTerminalName.trimmingCharacters(in: .whitespacesAndNewlines)
                let effectiveName = requestedName.isEmpty ? generatedTerminalName() : requestedName
                let list = try await codex.createManagedTerminal(
                    name: effectiveName,
                    cwd: cwd,
                    command: newTerminalCommand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    cols: 96,
                    rows: 32,
                    openVisible: openVisibleTerminalOnMac,
                    visibleApp: terminalVisibleApp.rpcValue
                )
                newTerminalName = ""
                isShowingCreateTerminalSheet = false
                rememberTerminalList(list, source: "create")
                if let pane = list.createdPane
                    ?? list.panes.first(where: { $0.sessionName == effectiveName && paneRequestTarget($0) != nil })
                    ?? list.panes.first(where: { paneRequestTarget($0) != nil }),
                   let target = paneRequestTarget(pane) {
                    localSelectedTerminalPaneTarget = target
                    try await codex.attachTerminalPane(target)
                }
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func rememberTerminalList(_ list: ManagedTerminalList, source: String) {
        visibleTerminalPanes = list.panes.filter { paneRequestTarget($0) != nil }
        let firstPane = list.panes.first?.paneDebugSummary ?? "none"
        terminalDebugLine = "\(source) terminal/list sessions=\(list.sessions.count) panes=\(list.panes.count) visible=\(visibleTerminalPanes.count) first=\(firstPane)"
        if let target = localSelectedTerminalPaneTarget,
           visibleTerminalPanes.contains(where: { $0.matches(target: target) }) {
            return
        }
        localSelectedTerminalPaneTarget = codex.selectedTerminalPane.flatMap(paneRequestTarget)
            ?? visibleTerminalPanes.first.flatMap(paneRequestTarget)
    }

    private func paneRequestTarget(_ pane: ManagedTerminalPane) -> String? {
        [
            pane.requestTarget,
            pane.paneId,
            pane.target,
            pane.paneKey,
            pane.paneAddress,
            pane.id,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: isUsablePaneTarget)
    }

    private func isUsablePaneTarget(_ target: String) -> Bool {
        guard !target.isEmpty,
              target != "unknown",
              target != ":",
              target != ":.",
              target != "::",
              !target.hasPrefix(":"),
              !target.hasSuffix(":"),
              !target.hasSuffix(".") else {
            return false
        }
        return true
    }

    private func stableTerminalDimensions(for size: CGSize) -> (cols: Int, rows: Int) {
        (
            cols: stableTerminalColumns(for: size.width),
            rows: max(8, min(80, Int(max(size.height - 24, 1) / 15)))
        )
    }

    private func stableTerminalColumns(for width: CGFloat) -> Int {
        max(36, min(120, Int(max(width - 28, 1) / 7.4)))
    }

    private func wrapTerminalDisplayText(_ text: String, columns: Int) -> String {
        guard columns > 0 else { return text }
        let expanded = text.replacingOccurrences(of: "\t", with: "    ")
        return expanded
            .split(separator: "\n", omittingEmptySubsequences: false)
            .flatMap { wrapTerminalLine(String($0), columns: columns) }
            .joined(separator: "\n")
    }

    private func wrapTerminalLine(_ line: String, columns: Int) -> [String] {
        guard !line.isEmpty else { return [""] }
        var lines: [String] = []
        var current = ""
        var currentWidth = 0
        for character in line {
            let width = terminalDisplayWidth(of: character)
            if currentWidth + width > columns, !current.isEmpty {
                lines.append(current)
                current = ""
                currentWidth = 0
            }
            current.append(character)
            currentWidth += width
        }
        lines.append(current)
        return lines
    }

    private func terminalDisplayWidth(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first else { return 1 }
        let value = scalar.value
        if (0x0300...0x036F).contains(value) {
            return 0
        }
        if (0x1100...0x115F).contains(value)
            || (0x2E80...0xA4CF).contains(value)
            || (0xAC00...0xD7A3).contains(value)
            || (0xF900...0xFAFF).contains(value)
            || (0xFE10...0xFE19).contains(value)
            || (0xFE30...0xFE6F).contains(value)
            || (0xFF00...0xFF60).contains(value)
            || (0xFFE0...0xFFE6).contains(value) {
            return 2
        }
        return 1
    }

}

struct TmuxCheatsheetView: View {
    let sessionName: String?

    private var sessionPlaceholder: String {
        let trimmed = sessionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "<session>" : trimmed
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(LocalizationManager.shared.localized("terminal.cheatsheet.summary"))
                    .font(AppFont.callout())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                tmuxCheatsheetSection(
                    titleKey: "terminal.cheatsheet.mental_model.title",
                    bodyKey: "terminal.cheatsheet.mental_model.body",
                    command: "Ghostty -> tmux client -> tmux pane -> Claude/Codex"
                )

                tmuxCheatsheetSection(
                    titleKey: "terminal.cheatsheet.attach.title",
                    bodyKey: "terminal.cheatsheet.attach.body",
                    command: "tmux ls\nmms-remote terminal join \(sessionPlaceholder)\ntmux attach -t \(sessionPlaceholder)"
                )

                tmuxCheatsheetSection(
                    titleKey: "terminal.cheatsheet.detach.title",
                    bodyKey: "terminal.cheatsheet.detach.body",
                    command: "Ctrl-b\nthen d"
                )

                tmuxCheatsheetSection(
                    titleKey: "terminal.cheatsheet.scroll.title",
                    bodyKey: "terminal.cheatsheet.scroll.body",
                    command: "Ctrl-b [\nPgUp / PgDn / mouse wheel\nq"
                )

                tmuxCheatsheetSection(
                    titleKey: "terminal.cheatsheet.resize.title",
                    bodyKey: "terminal.cheatsheet.resize.body",
                    command: "Ctrl-b : resize-window -A\ntmux resize-window -A\ntmux set -g window-size largest"
                )

                tmuxCheatsheetSection(
                    titleKey: "terminal.cheatsheet.kill.title",
                    bodyKey: "terminal.cheatsheet.kill.body",
                    command: "Ctrl-c, then Ctrl-c again\nCtrl-b x, then y\ntmux kill-session -t \(sessionPlaceholder)"
                )
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func tmuxCheatsheetSection(
        titleKey: String,
        bodyKey: String,
        command: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizationManager.shared.localized(titleKey))
                .font(AppFont.subheadline(weight: .semibold))
            Text(LocalizationManager.shared.localized(bodyKey))
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(command)
                .font(AppFont.mono(.caption))
                .foregroundStyle(Color(.label))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
