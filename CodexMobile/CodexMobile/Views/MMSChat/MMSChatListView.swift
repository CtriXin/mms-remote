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
                    Image(systemName: "slider.horizontal.3")
                }
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
            MMSChatDetailView(session: session)
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
            Button(LocalizationManager.shared.localized("mmschat.model_picker.open")) {
                isShowingLaunchPlanSheet = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(!codex.isConnected)
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
                        MMSChatSessionRowView(session: session) {
                            selectedSessionId = session.mmschatId
                        }
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
        let sessions: [MMSChatSession]
    }

    private var groupedSessions: [SessionGroup] {
        let sorted = sessions.sorted { $0.lastActivityAt > $1.lastActivityAt }
        let grouped = Dictionary(grouping: sorted) { session -> String in
            session.project ?? session.cwd.components(separatedBy: "/").last ?? session.cwd
        }
        return grouped
            .map { SessionGroup(key: $0.key, sessions: $0.value) }
            .sorted { group1, group2 in
                guard let latest1 = group1.sessions.first?.lastActivityAt,
                      let latest2 = group2.sessions.first?.lastActivityAt else {
                    return group1.key < group2.key
                }
                return latest1 > latest2
            }
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
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
