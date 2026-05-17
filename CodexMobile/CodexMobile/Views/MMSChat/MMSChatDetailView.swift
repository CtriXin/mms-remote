// FILE: MMSChatDetailView.swift
// Purpose: MMSChat session detail with transcript snapshot, structured messages, and raw fallback.
// Layer: View
// Exports: MMSChatDetailView

import SwiftUI

struct MMSChatDetailView: View {
    @Environment(CodexService.self) private var codex

    let session: MMSChatSession
    let onHidden: (MMSChatSession) -> Void

    @State private var detailResponse: MMSChatDetailResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showHideConfirmation = false
    @State private var showCacheClearConfirmation = false
    @State private var cacheClearResultMessage: String?
    @State private var showCacheClearResult = false
    @Environment(\.dismiss) private var dismiss

    init(session: MMSChatSession, onHidden: @escaping (MMSChatSession) -> Void = { _ in }) {
        self.session = session
        self.onHidden = onHidden
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sessionHeader
                transcriptSection
                sendDisabledBanner
            }
            .padding(16)
        }
        .navigationTitle(session.title ?? LocalizationManager.shared.localized("mmschat.detail_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showHideConfirmation = true
                    } label: {
                        Label(LocalizationManager.shared.localized("mmschat.detail.hide"), systemImage: "archivebox")
                    }

                    Button {
                        showCacheClearConfirmation = true
                    } label: {
                        Label(LocalizationManager.shared.localized("mmschat.detail.cache_clear"), systemImage: "xmark.bin")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(!codex.isConnected || isLoading)

                Button {
                    Task { await openVisible() }
                } label: {
                    Image(systemName: "display")
                }
                .disabled(!codex.isConnected || isLoading)

                Button {
                    Task { await loadDetail() }
                } label: {
                    if isLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(!codex.isConnected || isLoading)
            }
        }
        .task {
            await loadDetail()
        }
        .alert(
            LocalizationManager.shared.localized("mmschat.error_title"),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(LocalizationManager.shared.localized("common.ok"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .alert(
            LocalizationManager.shared.localized("mmschat.row.hide_confirm_title"),
            isPresented: $showHideConfirmation
        ) {
            Button(LocalizationManager.shared.localized("common.cancel"), role: .cancel) {}
            Button(LocalizationManager.shared.localized("mmschat.row.hide"), role: .destructive) {
                Task { await hideSession() }
            }
        } message: {
            Text(LocalizationManager.shared.localized("mmschat.row.hide_confirm_message"))
        }
        .alert(
            LocalizationManager.shared.localized("mmschat.detail.cache_clear_confirm_title"),
            isPresented: $showCacheClearConfirmation
        ) {
            Button(LocalizationManager.shared.localized("common.cancel"), role: .cancel) {}
            Button(LocalizationManager.shared.localized("mmschat.detail.cache_clear"), role: .destructive) {
                Task { await clearCache() }
            }
        } message: {
            Text(LocalizationManager.shared.localized("mmschat.detail.cache_clear_confirm_message"))
        }
        .alert(
            LocalizationManager.shared.localized("mmschat.detail.cache_clear"),
            isPresented: $showCacheClearResult
        ) {
            Button(LocalizationManager.shared.localized("common.ok"), role: .cancel) {}
        } message: {
            Text(cacheClearResultMessage ?? "")
        }
    }

    // MARK: - Session Header

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusBadge

                Text(session.title ?? session.project ?? session.cwd)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                if let provider = session.provider {
                    Label(provider, systemImage: "server.rack")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                if let model = session.model {
                    Label(model, systemImage: "cpu")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }

            Label(cwdDisplay, systemImage: "folder")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            HStack(spacing: 12) {
                Label(dateString(session.createdAt), systemImage: "calendar")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Label(dateString(session.lastActivityAt), systemImage: "clock")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var statusBadge: some View {
        let color: Color = switch session.status {
        case .running: .green
        case .idle: .yellow
        case .pending: .orange
        case .needsResume: .blue
        case .dead: .gray
        case .unknown: Color(.systemGray4)
        }
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(session.status.rawValue)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Transcript

    private var transcriptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizationManager.shared.localized("mmschat.transcript_title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let transcript = detailResponse?.transcript {
                transcriptContent(transcript)
            } else {
                Text(LocalizationManager.shared.localized("mmschat.transcript_unavailable"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func transcriptContent(_ transcript: MMSChatTranscriptSnapshot) -> some View {
        if !transcript.messages.isEmpty {
            structuredMessages(transcript.messages)
        } else if let raw = transcript.rawPreviewText, !raw.isEmpty {
            rawPreview(raw)
        } else {
            Text(LocalizationManager.shared.localized("mmschat.transcript_empty"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func structuredMessages(_ messages: [MMSChatTranscriptMessage]) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(messages) { message in
                messageBubble(message)
            }
        }
    }

    private func messageBubble(_ message: MMSChatTranscriptMessage) -> some View {
        let isUser = message.role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(message.role.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                ForEach(Array(message.content.enumerated()), id: \.offset) { _, content in
                    if let text = content.text, !text.isEmpty {
                        Text(text)
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(10)
            .background(isUser ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            if !isUser { Spacer(minLength: 40) }
        }
    }

    private func rawPreview(_ text: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    // MARK: - Send (Disabled)

    private var sendDisabledBanner: some View {
        HStack {
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
            Text(LocalizationManager.shared.localized("mmschat.send_disabled"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(10)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Helpers

    private var cwdDisplay: String {
        let path = session.cwd
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - Actions

    private func loadDetail() async {
        guard codex.isConnected else {
            errorMessage = LocalizationManager.shared.localized("mmschat.error_disconnected")
            return
        }
        isLoading = true
        do {
            detailResponse = try await codex.mmschatDetail(mmschatId: session.mmschatId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func openVisible() async {
        guard codex.isConnected else { return }
        do {
            _ = try await codex.mmschatOpenVisible(mmschatId: session.mmschatId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func hideSession() async {
        guard codex.isConnected else { return }
        do {
            let response = try await codex.mmschatHide(mmschatId: session.mmschatId, hidden: true)
            onHidden(response.session)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearCache() async {
        guard codex.isConnected else { return }
        isLoading = true
        do {
            let response = try await codex.mmschatCacheClear(mmschatId: session.mmschatId)
            cacheClearResultMessage = response.cacheCleared
                ? LocalizationManager.shared.localized("mmschat.detail.cache_clear_success")
                : LocalizationManager.shared.localized("mmschat.detail.cache_clear_error")
            showCacheClearResult = true
            await loadDetail()
        } catch {
            cacheClearResultMessage = error.localizedDescription
            showCacheClearResult = true
        }
        isLoading = false
    }
}
