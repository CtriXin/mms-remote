// FILE: MMSChatListView.swift
// Purpose: MMSChat session list with loading/empty/error states, grouped by project/cwd.
// Layer: View
// Exports: MMSChatListView

import SwiftUI

struct MMSChatListView: View {
    @Environment(CodexService.self) private var codex

    @State private var sessions: [MMSChatSession] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedSessionId: String?
    @State private var isShowingLaunchPlanSheet = false
    @State private var isSeedingDemo = false

    var body: some View {
        Group {
            if isLoading && sessions.isEmpty {
                loadingView
            } else if let errorMessage {
                errorView(message: errorMessage)
            } else if sessions.isEmpty {
                emptyView
            } else {
                sessionList
            }
        }
        .navigationTitle(LocalizationManager.shared.localized("mmschat.list_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingLaunchPlanSheet = true
                } label: {
                    Label(LocalizationManager.shared.localized("mmschat.model_picker.open"), systemImage: "plus.bubble")
                }
                .accessibilityLabel(LocalizationManager.shared.localized("mmschat.model_picker.open"))
                .accessibilityHint(LocalizationManager.shared.localized("mmschat.model_picker.open_hint"))
                .help(LocalizationManager.shared.localized("mmschat.model_picker.open_hint"))
                .labelStyle(.titleAndIcon)
                .disabled(!codex.isConnected)

                Button {
                    Task { await refresh() }
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
            await refresh()
        }
        .refreshable {
            await refresh()
        }
        .sheet(isPresented: $isShowingLaunchPlanSheet) {
            MMSChatLaunchPlanSheetView(defaultCwd: defaultLaunchCwd)
        }
        .navigationDestination(item: Binding(
            get: { selectedSessionId.flatMap { id in sessions.first { $0.mmschatId == id } } },
            set: { selectedSessionId = $0?.mmschatId }
        )) { session in
            MMSChatDetailView(session: session) { hiddenSession in
                sessions.removeAll { $0.mmschatId == hiddenSession.mmschatId }
                selectedSessionId = nil
            }
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text(LocalizationManager.shared.localized("mmschat.loading"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label(
                LocalizationManager.shared.localized("mmschat.empty_title"),
                systemImage: "bubble.left.and.bubble.right"
            )
        } description: {
            Text(LocalizationManager.shared.localized("mmschat.empty_description"))
        } actions: {
            VStack(spacing: 8) {
                Button {
                    Task { await refresh() }
                } label: {
                    Label(LocalizationManager.shared.localized("mmschat.empty_action_refresh"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(!codex.isConnected)

                Button {
                    isShowingLaunchPlanSheet = true
                } label: {
                    Label(LocalizationManager.shared.localized("mmschat.model_picker.open"), systemImage: "plus.bubble")
                }
                .buttonStyle(.bordered)
                .disabled(!codex.isConnected)

                Button {
                    Task { await seedDemo() }
                } label: {
                    if isSeedingDemo {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Label(LocalizationManager.shared.localized("mmschat.empty_action_demo"), systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!codex.isConnected || isSeedingDemo)

                Text(LocalizationManager.shared.localized("mmschat.empty_demo_hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorView(message: String) -> some View {
        ContentUnavailableView {
            Label(
                LocalizationManager.shared.localized("mmschat.error_title"),
                systemImage: "exclamationmark.triangle"
            )
        } description: {
            Text(message)
        } actions: {
            Button(LocalizationManager.shared.localized("mmschat.retry")) {
                Task { await refresh() }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        List {
            ForEach(groupedSessions, id: \.key) { group in
                Section {
                    ForEach(group.sessions) { session in
                        MMSChatSessionRowView(
                            session: session,
                            onTap: { selectedSessionId = session.mmschatId },
                            onHide: { Task { await hideSession(session) } }
                        )
                    }
                } header: {
                    Text(group.key)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Grouping

    private struct SessionGroup {
        let key: String
        var sessions: [MMSChatSession]
    }

    private var groupedSessions: [SessionGroup] {
        let sorted = sessions.sorted(by: compareSessionsForDisplay)
        var groups: [SessionGroup] = []
        var indexByKey: [String: Int] = [:]
        for session in sorted {
            let key = session.project ?? session.cwd.components(separatedBy: "/").last ?? session.cwd
            if let index = indexByKey[key] {
                groups[index].sessions.append(session)
            } else {
                indexByKey[key] = groups.count
                groups.append(SessionGroup(key: key, sessions: [session]))
            }
        }
        return groups.sorted { left, right in
            let leftSession = left.sessions.first
            let rightSession = right.sessions.first
            if let leftSession, let rightSession, compareSessionsForDisplay(leftSession, rightSession) != compareSessionsForDisplay(rightSession, leftSession) {
                return compareSessionsForDisplay(leftSession, rightSession)
            }
            return left.key.localizedStandardCompare(right.key) == .orderedAscending
        }
    }

    private func compareSessionsForDisplay(_ left: MMSChatSession, _ right: MMSChatSession) -> Bool {
        let leftRank = activityQualityRank(left)
        let rightRank = activityQualityRank(right)
        if leftRank != rightRank { return leftRank < rightRank }
        if left.lastActivityAt != right.lastActivityAt { return left.lastActivityAt > right.lastActivityAt }
        if left.createdAt != right.createdAt { return left.createdAt > right.createdAt }
        return left.mmschatId.localizedStandardCompare(right.mmschatId) == .orderedAscending
    }

    private func activityQualityRank(_ session: MMSChatSession) -> Int {
        let messageCount = Int(session.metadata?["messageCount"] ?? "") ?? 0
        let isEmptyCodexRollout = session.provider == "codex"
            && session.metadata?["source"] == "codex-rollout"
            && (session.transcriptCacheState == .empty || messageCount == 0)
        return isEmptyCodexRollout ? 1 : 0
    }

    private var defaultLaunchCwd: String {
        sessions.first?.cwd ?? "/"
    }

    // MARK: - Actions

    private func refresh() async {
        guard codex.isConnected else {
            errorMessage = LocalizationManager.shared.localized("mmschat.error_disconnected")
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let response = try await codex.mmschatList()
            sessions = response.sessions.filter { !$0.hidden }
        } catch {
            errorMessage = MMSChatErrorClassifier.localizedMessage(for: error)
        }
        isLoading = false
    }

    private func seedDemo() async {
        guard codex.isConnected else {
            errorMessage = LocalizationManager.shared.localized("mmschat.error_disconnected")
            return
        }
        isSeedingDemo = true
        errorMessage = nil
        do {
            let response = try await codex.mmschatDemoSeed()
            sessions = response.sessions.filter { !$0.hidden }
        } catch {
            errorMessage = MMSChatErrorClassifier.localizedMessage(for: error)
        }
        isSeedingDemo = false
    }

    private func hideSession(_ session: MMSChatSession) async {
        guard codex.isConnected else { return }
        do {
            _ = try await codex.mmschatHide(mmschatId: session.mmschatId, hidden: true)
            sessions.removeAll { $0.mmschatId == session.mmschatId }
        } catch {
            errorMessage = MMSChatErrorClassifier.localizedMessage(for: error)
        }
    }
}
