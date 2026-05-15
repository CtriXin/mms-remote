// FILE: TerminalHubView.swift
// Purpose: Basic managed terminal mode UI for listing panes, viewing snapshots, and sending input.
// Layer: View
// Exports: TerminalHubView
// Depends on: SwiftUI, UIKit, CodexService, TerminalModels, AppFont

import SwiftUI
import UIKit

struct TerminalHubView: View {
    @Environment(CodexService.self) private var codex

    let onClose: () -> Void

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

    var body: some View {
        VStack(spacing: 0) {
            if !codex.isConnected {
                terminalOfflineBanner
            }

            if codex.terminalPanes.isEmpty && !codex.isLoadingTerminals {
                emptyState
            } else {
                terminalContent
            }
        }
        .navigationTitle("Terminals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Chats", action: onClose)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    openCreateTerminalSheet()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(!codex.isConnected || isCreatingTerminal)
                .accessibilityLabel("New terminal")

                Button(role: .destructive) {
                    panePendingClose = codex.selectedTerminalPane
                } label: {
                    if isClosingTerminal {
                        ProgressView()
                    } else {
                        Image(systemName: "xmark.circle")
                    }
                }
                .disabled(!codex.isConnected || codex.selectedTerminalPane == nil || isClosingTerminal)
                .accessibilityLabel("Close selected terminal")

                Button {
                    openSelectedPaneOnMac()
                } label: {
                    if isOpeningVisibleTerminal {
                        ProgressView()
                    } else {
                        Image(systemName: "display")
                    }
                }
                .disabled(!codex.isConnected || codex.selectedTerminalPaneId == nil || isOpeningVisibleTerminal)
                .accessibilityLabel("Open selected terminal on Mac")

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
                .accessibilityLabel("Refresh terminals")
            }
        }
        .task {
            if codex.isConnected {
                codex.resetManagedTerminalState()
                await refreshTerminalsAsync()
            }
        }
        .task(id: codex.isConnected) {
            await pollTerminalList()
        }
        .task(id: codex.selectedTerminalPaneId) {
            await pollSelectedPaneSnapshot(paneId: codex.selectedTerminalPaneId)
        }
        .alert("Terminal Error", isPresented: terminalErrorIsPresented) {
            Button("OK", role: .cancel) {
                localErrorMessage = nil
            }
        } message: {
            Text(localErrorMessage ?? "Terminal request failed.")
        }
        .confirmationDialog(
            "Close Terminal?",
            isPresented: closeDialogIsPresented,
            titleVisibility: .visible
        ) {
            if let pane = panePendingClose {
                Button("Close \(pane.displayTitle)", role: .destructive) {
                    closePane(pane)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Kills tmux pane \(panePendingClose?.paneKey ?? "") on Mac and phone.")
        }
        .sheet(isPresented: $isShowingCreateTerminalSheet) {
            NavigationStack {
                ScrollView {
                    createTerminalCard
                        .padding(20)
                }
                .navigationTitle("New Terminal")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
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

            inputBar
                .padding(12)
                .background(Color(.systemBackground))
        }
    }

    private var paneStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(codex.terminalPanes) { pane in
                    Button {
                        attachPane(pane)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pane.displayTitle)
                                .font(AppFont.caption(weight: .semibold))
                                .lineLimit(1)
                            Text(pane.paneKey)
                                .font(AppFont.mono(.caption2))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minWidth: 118, alignment: .leading)
                        .background(paneChipBackground(for: pane), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(paneChipBorder(for: pane), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            copyJoinCommand(for: pane)
                        } label: {
                            Label("Copy Join Command", systemImage: "terminal")
                        }

                        Button {
                            copyPaneAddress(for: pane)
                        } label: {
                            Label("Copy Pane Address", systemImage: "number")
                        }

                        Button {
                            openVisiblePaneOnMac(pane)
                        } label: {
                            Label("Open on Mac", systemImage: "display")
                        }

                        Button(role: .destructive) {
                            panePendingClose = pane
                        } label: {
                            Label("Close Terminal", systemImage: "xmark.circle")
                        }
                    }
                }
            }
        }
    }

    private var terminalSnapshotView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(currentSnapshotText)
                    .font(AppFont.mono(.caption))
                    .foregroundStyle(Color(.label))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(14)
                    .id("terminal-bottom")
            }
            .background(Color(.systemBackground))
            .onChange(of: currentSnapshotText) { _, _ in
                proxy.scrollTo("terminal-bottom", anchor: .bottom)
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickKeys) { key in
                        Button(key.label) {
                            sendKey(key)
                        }
                        .font(AppFont.caption(weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                        .buttonStyle(.plain)
                        .disabled(!canSendInput)
                    }
                }
            }

            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(codex.selectedTerminalPaneId == nil ? Color(.tertiaryLabel) : .green)
                        .frame(width: 6, height: 6)
                    Text(codex.selectedTerminalPaneId == nil ? "No pane" : "Live")
                        .font(AppFont.caption2(weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .background(Color(.secondarySystemBackground), in: Capsule())

                TextField("Command", text: $commandDraft, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(AppFont.mono(.body))
                    .lineLimit(1...3)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onSubmit { sendCommand() }

                Button {
                    sendCommand()
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
                .disabled(!canSendInput || commandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("No managed terminals")
                .font(AppFont.title3(weight: .semibold))
            Text("Create a tmux-managed terminal on your Mac bridge, then control it from this phone.")
                .font(AppFont.callout())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            createTerminalCard
                .frame(maxWidth: 380)
            Spacer()
        }
        .padding(24)
    }

    private var createTerminalCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("New Terminal")
                .font(AppFont.subheadline(weight: .semibold))
            TextField("Name", text: $newTerminalName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField("Mac cwd, e.g. /Users/me/project", text: $newTerminalCwd)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField("Command (optional)", text: $newTerminalCommand)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            Toggle("Open Mac terminal app", isOn: $openVisibleTerminalOnMac)
                .font(AppFont.callout())
            Button {
                createTerminal()
            } label: {
                HStack {
                    if isCreatingTerminal { ProgressView() }
                    Text("Create Managed Terminal")
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
            Text("Connect to your Mac bridge before using managed terminals.")
                .font(AppFont.caption(weight: .medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(Color(.tertiarySystemFill))
    }

    private var currentSnapshot: ManagedTerminalSnapshot? {
        guard let paneId = codex.selectedTerminalPaneId else { return nil }
        return codex.terminalSnapshotsByPaneId[paneId]
    }

    private var currentSnapshotText: String {
        currentSnapshot?.content.isEmpty == false ? currentSnapshot?.content ?? "" : "Select a pane, then use refresh or input to load output."
    }

    private var canSendInput: Bool {
        codex.isConnected && codex.selectedTerminalPaneId != nil && !isSendingInput
    }

    private var quickKeys: [ManagedTerminalKey] {
        [.ctrlC, .tab, .escape, .up, .down, .left, .right]
    }

    private var terminalErrorIsPresented: Binding<Bool> {
        Binding(
            get: { localErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    localErrorMessage = nil
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

    private func paneChipBackground(for pane: ManagedTerminalPane) -> Color {
        isSelected(pane) ? Color.primary.opacity(0.12) : Color(.systemBackground)
    }

    private func paneChipBorder(for pane: ManagedTerminalPane) -> Color {
        isSelected(pane) ? Color.primary.opacity(0.45) : Color.primary.opacity(0.08)
    }

    private func isSelected(_ pane: ManagedTerminalPane) -> Bool {
        codex.selectedTerminalPaneId == pane.paneId || codex.selectedTerminalPaneId == pane.paneKey
    }

    private func refreshTerminals() {
        Task { await refreshTerminalsAsync() }
    }

    private func refreshTerminalsAsync() async {
        guard codex.isConnected else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            localErrorMessage = nil
            try await codex.refreshTerminalList()
            if let pane = codex.selectedTerminalPane {
                try await codex.refreshTerminalSnapshot(paneId: pane.paneId)
            }
        } catch {
            localErrorMessage = error.localizedDescription
        }
    }

    private func pollTerminalList() async {
        while !Task.isCancelled {
            if codex.isConnected {
                do {
                    try await codex.refreshTerminalList(showLoading: false)
                } catch {
                    // Background list polling must not block the terminal UI with stale alerts.
                }
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }

    private func pollSelectedPaneSnapshot(paneId: String?) async {
        guard let paneId, !paneId.isEmpty else { return }
        while !Task.isCancelled {
            guard codex.isConnected, codex.selectedTerminalPaneId == paneId else { return }
            do {
                try await codex.refreshTerminalSnapshot(paneId: paneId)
            } catch {
                if !Task.isCancelled {
                    try? await codex.refreshTerminalList(showLoading: false)
                }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
    }

    private func attachPane(_ pane: ManagedTerminalPane) {
        Task {
            do {
                try await codex.attachTerminalPane(pane.paneId)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func sendCommand() {
        let command = commandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        commandDraft = ""
        Task {
            isSendingInput = true
            defer { isSendingInput = false }
            do {
                try await codex.sendTerminalText(command)
                try await codex.sendTerminalKey(.enter)
                try? await Task.sleep(nanoseconds: 180_000_000)
                try await codex.refreshTerminalSnapshot()
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func sendKey(_ key: ManagedTerminalKey) {
        Task {
            do {
                try await codex.sendTerminalKey(key)
                try? await Task.sleep(nanoseconds: 120_000_000)
                try await codex.refreshTerminalSnapshot()
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func openSelectedPaneOnMac() {
        guard let pane = codex.selectedTerminalPane else { return }
        openVisiblePaneOnMac(pane)
    }

    private func openVisiblePaneOnMac(_ pane: ManagedTerminalPane) {
        Task {
            isOpeningVisibleTerminal = true
            defer { isOpeningVisibleTerminal = false }
            do {
                try await codex.openVisibleTerminalPane(pane.paneId)
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    private func copyJoinCommand(for pane: ManagedTerminalPane) {
        UIPasteboard.general.string = "mms-remote terminal join \(pane.paneKey)"
    }

    private func copyPaneAddress(for pane: ManagedTerminalPane) {
        UIPasteboard.general.string = pane.paneKey
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
                try await codex.killTerminalPane(pane.paneId)
                try? await Task.sleep(nanoseconds: 200_000_000)
                try await codex.refreshTerminalList(showLoading: false)
                if let nextPane = codex.selectedTerminalPane {
                    try await codex.attachTerminalPane(nextPane.paneId)
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
                    openVisible: openVisibleTerminalOnMac
                )
                newTerminalName = ""
                isShowingCreateTerminalSheet = false
                if let pane = list.panes.first(where: { $0.sessionName == effectiveName }) ?? list.panes.first {
                    try await codex.attachTerminalPane(pane.paneId)
                }
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
