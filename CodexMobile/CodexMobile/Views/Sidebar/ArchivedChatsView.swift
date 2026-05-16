// FILE: ArchivedChatsView.swift
// Purpose: Displays all archived chats with unarchive and delete actions.
// Layer: View
// Exports: ArchivedChatsView
// Depends on: CodexService, CodexThread

import SwiftUI

struct ArchivedChatsView: View {
    @Environment(CodexService.self) private var codex
    @State private var threadPendingDeletion: CodexThread? = nil

    private var archivedThreads: [CodexThread] {
        codex.threads
            .filter { $0.syncState == .archivedLocal }
            .sorted {
                let lhsDate = $0.updatedAt ?? $0.createdAt ?? .distantPast
                let rhsDate = $1.updatedAt ?? $1.createdAt ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    var body: some View {
        Group {
            if archivedThreads.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 36))
                        .foregroundStyle(.tertiary)
                    Text(localized: "sidebar.no_archived_chats")
                        .font(AppFont.subheadline())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(archivedThreads) { thread in
                        archivedRow(thread)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(Text(localized: "settings.archived_chats"))
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Remove \"\(threadPendingDeletion?.displayTitle ?? "conversation")\" from this phone?",
            isPresented: Binding(
                get: { threadPendingDeletion != nil },
                set: { if !$0 { threadPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(LocalizationManager.shared.localized("sidebar.remove_from_phone"), role: .destructive) {
                if let thread = threadPendingDeletion {
                    codex.deleteThreadLocally(thread.id)
                }
                threadPendingDeletion = nil
            }
            Button(LocalizationManager.shared.localized("sidebar.cancel"), role: .cancel) {
                threadPendingDeletion = nil
            }
        } message: {
            Text(localized: "sidebar.remove_confirm")
        }
    }

    private func archivedRow(_ thread: CodexThread) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(thread.displayTitle)
                    .font(AppFont.body())
                    .lineLimit(1)

                if let date = thread.updatedAt ?? thread.createdAt {
                    Text(date, style: .relative)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                threadPendingDeletion = thread
            } label: {
                Label(LocalizationManager.shared.localized("sidebar.remove"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                codex.unarchiveThread(thread.id)
            } label: {
                Label(LocalizationManager.shared.localized("sidebar.unarchive"), systemImage: "tray.and.arrow.up")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                codex.unarchiveThread(thread.id)
            } label: {
                Label(LocalizationManager.shared.localized("sidebar.unarchive"), systemImage: "tray.and.arrow.up")
            }

            Button(role: .destructive) {
                threadPendingDeletion = thread
            } label: {
                Label(LocalizationManager.shared.localized("sidebar.remove_from_phone"), systemImage: "trash")
            }
        }
    }
}
