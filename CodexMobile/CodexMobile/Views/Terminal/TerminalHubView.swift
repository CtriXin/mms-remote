// FILE: TerminalHubView.swift
// Purpose: Basic managed terminal mode UI for listing panes, viewing snapshots, and sending input.
// Layer: View
// Exports: TerminalHubView
// Depends on: SwiftUI, CodexService, TerminalModels, AppFont

import SwiftUI

struct TerminalHubView: View {
    @Environment(CodexService.self) private var codex

    let onClose: () -> Void

    @State private var commandDraft = ""
    @State private var newTerminalName = ""
    @State private var newTerminalCwd = "/"
    @State private var newTerminalCommand = ""
    @State private var isRefreshing = false
    @State private var isSendingInput = false
    @State private var isCreatingTerminal = false
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
            ToolbarItem(placement: .topBarTrailing) {
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
            if codex.isConnected, codex.terminalPanes.isEmpty {
                await refreshTerminalsAsync()
            }
        }
        .task(id: codex.selectedTerminalPaneId) {
            await pollSelectedPaneSnapshot(paneId: codex.selectedTerminalPaneId)
        }
        .alert("Terminal Error", isPresented: terminalErrorIsPresented) {
            Button("OK", role: .cancel) {
                localErrorMessage = nil
                codex.terminalLastErrorMessage = nil
            }
        } message: {
            Text(localErrorMessage ?? codex.terminalLastErrorMessage ?? "Terminal request failed.")
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
            get: { localErrorMessage != nil || codex.terminalLastErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    localErrorMessage = nil
                    codex.terminalLastErrorMessage = nil
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
            try await codex.refreshTerminalList()
            if let pane = codex.selectedTerminalPane {
                try await codex.refreshTerminalSnapshot(paneId: pane.paneId)
            }
        } catch {
            localErrorMessage = error.localizedDescription
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
                    codex.terminalLastErrorMessage = error.localizedDescription
                }
                return
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

    private func createTerminal() {
        let cwd = newTerminalCwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cwd.isEmpty else { return }
        Task {
            isCreatingTerminal = true
            defer { isCreatingTerminal = false }
            do {
                let list = try await codex.createManagedTerminal(
                    name: newTerminalName.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    cwd: cwd,
                    command: newTerminalCommand.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                    cols: 96,
                    rows: 32
                )
                if let pane = list.panes.first(where: { $0.sessionName == newTerminalName }) ?? list.panes.first {
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
