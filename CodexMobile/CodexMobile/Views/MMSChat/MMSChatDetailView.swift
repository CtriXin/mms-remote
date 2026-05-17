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
    @State private var composerText = ""
    @State private var isSending = false
    @State private var isResuming = false
    @State private var inlineStatusMessage: String?
    @State private var inlineStatusIsError = false
    @State private var inlineStatusToken: UUID?
    @Environment(\.dismiss) private var dismiss
    private nonisolated static let transcriptBottomAnchorId = "mmschat-transcript-bottom"
    @State private var latestTranscriptScrollTokenForce = ""

    init(session: MMSChatSession, onHidden: @escaping (MMSChatSession) -> Void = { _ in }) {
        self.session = session
        self.onHidden = onHidden
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sessionHeader
                    transcriptSection
                    actionArea
                    inlineStatusView
                    Color.clear
                        .frame(height: 1)
                        .id(Self.transcriptBottomAnchorId)
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
                     .disabled(!codex.isConnected || !liveActionsEnabled || isLoading)

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
            .onChange(of: latestTranscriptScrollToken) { _, _ in
                scrollToLatest(scrollProxy)
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

    @ViewBuilder
    private func structuredMessages(_ messages: [MMSChatTranscriptMessage]) -> some View {
        let visibleMessages = messages.filter { !isHiddenTranscriptMessage($0) }
        if visibleMessages.isEmpty {
            Text(LocalizationManager.shared.localized("mmschat.transcript_empty"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        } else {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(visibleMessages) { message in
                    messageBubble(message)
                }
            }
        }
    }

    private func messageBubble(_ message: MMSChatTranscriptMessage) -> some View {
        let role = normalizedRole(message.role)
        let isUser = role == "user"
        return HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(roleTitle(role))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(roleTint(role))

                    if let createdAt = message.createdAt {
                        Text(dateString(createdAt))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                ForEach(Array(message.content.enumerated()), id: \.offset) { _, content in
                    messageContent(content, role: role)
                }
            }
            .padding(12)
            .background(roleBackground(role))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(roleTint(role).opacity(0.22), lineWidth: role == "assistant" ? 0 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if !isUser { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private func messageContent(_ content: MMSChatTranscriptContent, role: String) -> some View {
        if let text = content.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if shouldUseMonospacedContent(content, role: role) {
                Text(text)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(Color(.systemBackground).opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .textSelection(.enabled)
            } else {
                markdownText(text)
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
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

    private func isHiddenTranscriptMessage(_ message: MMSChatTranscriptMessage) -> Bool {
        let role = normalizedRole(message.role)
        if role == "system" || role == "developer" {
            return true
        }
        return message.content.allSatisfy { content in
            (content.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func normalizedRole(_ role: String) -> String {
        role.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func roleTitle(_ role: String) -> String {
        switch role {
        case "user":
            LocalizationManager.shared.localized("mmschat.role.user")
        case "assistant":
            LocalizationManager.shared.localized("mmschat.role.assistant")
        case "reasoning":
            LocalizationManager.shared.localized("mmschat.role.reasoning")
        case "tool":
            LocalizationManager.shared.localized("mmschat.role.tool")
        default:
            role.uppercased()
        }
    }

    private func roleTint(_ role: String) -> Color {
        return switch role {
        case "user": .accentColor
        case "assistant": .green
        case "reasoning": .orange
        case "tool": .blue
        default: .secondary
        }
    }

    private func roleBackground(_ role: String) -> Color {
        return switch role {
        case "user": Color.accentColor.opacity(0.12)
        case "assistant": Color(.tertiarySystemFill)
        case "reasoning": Color.orange.opacity(0.10)
        case "tool": Color.blue.opacity(0.10)
        default: Color(.secondarySystemGroupedBackground)
        }
    }

    private func shouldUseMonospacedContent(_ content: MMSChatTranscriptContent, role: String) -> Bool {
        role == "tool" || content.type == "tool_result" || content.type == "tool_use"
    }

    private func markdownText(_ text: String) -> Text {
        if let attributed = try? AttributedString(markdown: text) {
            return Text(attributed)
        }
        return Text(text)
    }

    // MARK: - Live Actions & Composer

    @ViewBuilder
    private var actionArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Read-only banner for Codex rollout
            if isCodexRollout {
                HStack(spacing: 6) {
                    Image(systemName: "lock.doc.fill")
                        .foregroundStyle(.secondary)
                    Text(LocalizationManager.shared.localized("mmschat.status.read_only"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(LocalizationManager.shared.localized("mmschat.status.read_only_detail"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            } else {
                // Live guard state banner
                HStack(spacing: 6) {
                    Image(systemName: liveActionsEnabled ? "bolt.circle.fill" : "lock.fill")
                        .foregroundStyle(liveActionsEnabled ? .green : .secondary)
                    Text(LocalizationManager.shared.localized(liveActionsEnabled ? "mmschat.live_enabled" : "mmschat.live_guard_disabled"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(liveActionsEnabled ? .green : .secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color(.tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                // Open Mac action
                HStack(spacing: 8) {
                    Button {
                        Task { await openVisible() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "display")
                            Text(LocalizationManager.shared.localized("mmschat.action.open_mac"))
                                .font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                    .disabled(!codex.isConnected || !liveActionsEnabled || isLoading)

                    Spacer()
                }

                // Resume action (only when resumable and guard allows)
                if canResume {
                    HStack(spacing: 8) {
                        Button {
                            Task { await resumeSession() }
                        } label: {
                            HStack(spacing: 4) {
                                if isResuming {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                }
                                Image(systemName: "play.circle")
                                Text(LocalizationManager.shared.localized(isResuming ? "mmschat.action.resuming" : "mmschat.action.resume"))
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(!codex.isConnected || !liveActionsEnabled || isLoading || isSending || isResuming)

                        Text(LocalizationManager.shared.localized("mmschat.resume_hint"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)

                        Spacer()
                    }
                }

                // Resume disabled reason
                if !canResume && liveActionsEnabled && session.status.resumable {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text(LocalizationManager.shared.localized("mmschat.resume_unavailable"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                }

                // Resume disabled by guard
                if !canResume && session.status.resumable && !liveActionsEnabled {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                        Text(LocalizationManager.shared.localized("mmschat.resume_disabled_guard"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                }

                Divider()

                // Composer with Send
                if canSend {
                    HStack(spacing: 8) {
                        TextField(
                            LocalizationManager.shared.localized("mmschat.composer.placeholder"),
                            text: $composerText,
                            axis: .vertical
                        )
                        .font(.system(size: 14))
                        .padding(10)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                        .lineLimit(1...5)
                        .disabled(!codex.isConnected || !liveActionsEnabled || isLoading || isSending)

                        Button {
                            Task { await sendMessage() }
                        } label: {
                            if isSending {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundStyle(composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : Color.accentColor)
                            }
                        }
                        .disabled(
                            !codex.isConnected || !liveActionsEnabled || isLoading || isSending ||
                            composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                } else if liveActionsEnabled {
                    // Send not in supported methods
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text(LocalizationManager.shared.localized("mmschat.send_unavailable"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                } else if !liveActionsEnabled {
                    // Send disabled by guard
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.secondary)
                        Text(LocalizationManager.shared.localized("mmschat.send_disabled_guard"))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var inlineStatusView: some View {
        if let message = inlineStatusMessage {
            HStack(spacing: 6) {
                Image(systemName: inlineStatusIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(inlineStatusIsError ? .red : .green)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(inlineStatusIsError ? .red : .green)
                Spacer()
            }
            .padding(8)
            .background(inlineStatusIsError ? Color.red.opacity(0.08) : Color.green.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onAppear {
                let token = UUID()
                inlineStatusToken = token
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [token] in
                    guard inlineStatusToken == token else { return }
                    withAnimation {
                        inlineStatusMessage = nil
                        inlineStatusIsError = false
                    }
                }
            }
        }
    }

    private var liveActionsEnabled: Bool {
        detailResponse?.liveActions?.enabled == true
    }

    private var isCodexRollout: Bool {
        session.provider == "codex"
            && session.metadata?["source"] == "codex-rollout"
    }

    private var liveActions: MMSChatLiveActionsState? {
        detailResponse?.liveActions
    }

    private var canResume: Bool {
        guard liveActionsEnabled, let la = liveActions else { return false }
        guard la.supportedMethods?.contains(where: { $0 == "mmschat/resume" || $0 == "resume" }) == true else {
            return false
        }
        return session.status.resumable || session.status == .idle
    }

    private var canSend: Bool {
        guard liveActionsEnabled, let la = liveActions else { return false }
        return la.supportedMethods?.contains(where: { $0 == "mmschat/send" || $0 == "send" }) == true
    }

    private var latestTranscriptScrollToken: String {
        guard let transcript = detailResponse?.transcript else { return "" }
        return [
            transcript.source.rawValue,
            String(transcript.messages.count),
            String(transcript.rawPreviewText?.count ?? 0),
            latestTranscriptScrollTokenForce,
        ].joined(separator: ":")
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

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard !latestTranscriptScrollToken.isEmpty else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(Self.transcriptBottomAnchorId, anchor: .bottom)
            }
        }
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

    private func resumeSession() async {
        guard codex.isConnected, canResume else { return }
        isResuming = true
        inlineStatusMessage = nil
        do {
            let response = try await codex.mmschatResume(mmschatId: session.mmschatId)
            if response.resumeStarted {
                inlineStatusMessage = LocalizationManager.shared.localized("mmschat.resume_success")
                inlineStatusIsError = false
                await loadDetail()
                latestTranscriptScrollTokenForce = UUID().uuidString
            } else {
                inlineStatusMessage = LocalizationManager.shared.localized("mmschat.resume_not_started")
                inlineStatusIsError = true
            }
        } catch {
            inlineStatusMessage = error.localizedDescription
            inlineStatusIsError = true
        }
        isResuming = false
    }

    private func sendMessage() async {
        let text = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard codex.isConnected, canSend, !text.isEmpty else { return }
        isSending = true
        inlineStatusMessage = nil
        do {
            let response = try await codex.mmschatSend(mmschatId: session.mmschatId, text: text)
            if response.accepted {
                composerText = ""
                inlineStatusMessage = LocalizationManager.shared.localized("mmschat.send_success")
                inlineStatusIsError = false
                await loadDetail()
                latestTranscriptScrollTokenForce = UUID().uuidString
            } else {
                inlineStatusMessage = LocalizationManager.shared.localized("mmschat.send_rejected")
                inlineStatusIsError = true
            }
        } catch {
            inlineStatusMessage = error.localizedDescription
            inlineStatusIsError = true
        }
        isSending = false
    }
}
