// FILE: MMSChatSessionRowView.swift
// Purpose: Displays a single MMSChat session row in the list.
// Layer: View Component
// Exports: MMSChatSessionRowView

import SwiftUI

struct MMSChatSessionRowView: View {
    let session: MMSChatSession
    let onTap: () -> Void
    let onHide: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 10) {
                statusIcon
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(sessionTitle)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let provider = session.provider {
                            Text(provider)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        if let model = session.model {
                            Label(model, systemImage: "cpu")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text(cwdAbbreviated)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    if let preview = session.lastPreviewText, !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(relativeTimeString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Text(lastActivitySubtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive, action: onHide) {
                Label(LocalizationManager.shared.localized("mmschat.row.hide"), systemImage: "archivebox")
            }
            .tint(.orange)
        }
    }

    // MARK: - Components

    @ViewBuilder
    private var statusIcon: some View {
        switch session.status {
        case .running:
            Circle().fill(.green)
        case .idle:
            Circle().fill(.yellow)
        case .pending:
            Circle().fill(.orange)
        case .needsResume:
            Circle().fill(.blue)
        case .dead:
            Circle().fill(.gray)
        case .unknown:
            Circle().fill(Color(.systemGray4))
        }
    }

    private var sessionTitle: String {
        session.title
            ?? session.project
            ?? session.cwd.components(separatedBy: "/").last
            ?? session.mmschatId
    }

    private var cwdAbbreviated: String {
        let path = session.cwd
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private var relativeTimeString: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: session.lastActivityAt, relativeTo: Date())
    }

    private var lastActivitySubtitle: String {
        String(
            format: LocalizationManager.shared.localized("mmschat.row.last_activity_format"),
            exactActivityString
        )
    }

    private var exactActivityString: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: session.lastActivityAt)
    }
}
