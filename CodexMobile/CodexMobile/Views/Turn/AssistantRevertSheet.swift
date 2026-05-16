// FILE: AssistantRevertSheet.swift
// Purpose: Presents preview, conflicts, and confirmation for assistant-scoped revert actions.
// Layer: View Component
// Exports: AssistantRevertSheet, AssistantRevertSheetState
// Depends on: SwiftUI, AIChangeSetModels

import SwiftUI

struct AssistantRevertSheetState: Identifiable, Equatable {
    let changeSet: AIChangeSet
    let presentation: AssistantRevertPresentation
    var preview: RevertPreviewResult?
    var isLoadingPreview: Bool
    var isApplying: Bool
    var errorMessage: String?

    var id: String { changeSet.id }
}

struct AssistantRevertSheet: View {
    let state: AssistantRevertSheetState
    let onClose: () -> Void
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var affectedFiles: [String] {
        if let preview = state.preview, !preview.affectedFiles.isEmpty {
            return preview.affectedFiles
        }
        return state.changeSet.fileChanges.map(\.path)
    }

    private var totalAdditions: Int {
        state.changeSet.fileChanges.reduce(0) { $0 + $1.additions }
    }

    private var totalDeletions: Int {
        state.changeSet.fileChanges.reduce(0) { $0 + $1.deletions }
    }

    private var canConfirm: Bool {
        guard let preview = state.preview else { return false }
        return preview.canRevert && !state.isLoadingPreview && !state.isApplying
    }

    // Uses preview outcome as the final gate while preserving the initial safe/warning intent.
    private var effectiveRiskLevel: AssistantRevertRiskLevel {
        if let preview = state.preview, !preview.canRevert {
            return .blocked
        }
        if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
            return .blocked
        }
        return state.presentation.riskLevel
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    infoCard

                    if state.isLoadingPreview {
                        loadingCard
                    } else if let preview = state.preview {
                        previewCard(preview)
                    }

                    if let errorMessage = state.errorMessage, !errorMessage.isEmpty {
                        errorCard(errorMessage)
                    }
                }
                .padding(16)
            }
            .navigationTitle(LocalizationManager.shared.localized("revert.title"))
            .navigationBarTitleDisplayMode(.inline)
            .adaptiveNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizationManager.shared.localized("settings.close")) {
                        dismiss()
                        onClose()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if canConfirm {
                        Button(state.isApplying ? LocalizationManager.shared.localized("revert.undoing") : LocalizationManager.shared.localized("revert.undo")) {
                            onConfirm()
                        }
                        .disabled(state.isApplying)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizationManager.shared.localized("revert.description"))
                .font(AppFont.body())
                .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Text(String(format: LocalizationManager.shared.localized("revert.files"), affectedFiles.count))
                    .font(AppFont.mono(.caption))
                    .foregroundStyle(.secondary)
                Text("+\(totalAdditions)")
                    .font(AppFont.mono(.caption))
                    .foregroundStyle(.green)
                Text("-\(totalDeletions)")
                    .font(AppFont.mono(.caption))
                    .foregroundStyle(.red)
            }

            if !affectedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(affectedFiles, id: \.self) { path in
                        Text(path)
                            .font(AppFont.mono(.caption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            if effectiveRiskLevel == .warning {
                issueSection(
                    title: LocalizationManager.shared.localized("revert.needs_review"),
                    lines: warningLines
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
            Text(LocalizationManager.shared.localized("revert.checking"))
                .font(AppFont.body())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func previewCard(_ preview: RevertPreviewResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            previewStatusLabel(preview)

            if !preview.stagedFiles.isEmpty {
                issueSection(
                    title: LocalizationManager.shared.localized("revert.staged_files"),
                    lines: preview.stagedFiles.map {
                        "\($0): Unstage this file first to keep revert predictable."
                    }
                )
            }

            if !preview.unsupportedReasons.isEmpty {
                issueSection(title: LocalizationManager.shared.localized("revert.unsupported"), lines: preview.unsupportedReasons)
            }

            if !preview.conflicts.isEmpty {
                issueSection(
                    title: LocalizationManager.shared.localized("revert.conflicts"),
                    lines: preview.conflicts.map { "\($0.path): \($0.message)" }
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .adaptiveGlass(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var warningLines: [String] {
        var lines: [String] = []
        if let warningText = state.presentation.warningText, !warningText.isEmpty {
            lines.append(warningText)
        }
        lines.append(contentsOf: state.presentation.overlappingFiles.map { "\($0): also touched by another chat." })
        return lines
    }

    @ViewBuilder
    private func previewStatusLabel(_ preview: RevertPreviewResult) -> some View {
        switch effectiveRiskLevel {
        case .safe:
            Label(LocalizationManager.shared.localized("revert.clean"), systemImage: "checkmark.circle.fill")
                .font(AppFont.body(weight: .semibold))
                .foregroundStyle(.green)
        case .warning:
            if preview.canRevert {
                Label(LocalizationManager.shared.localized("revert.partial"), systemImage: "exclamationmark.circle.fill")
                    .font(AppFont.body(weight: .semibold))
                    .foregroundStyle(.orange)
            } else {
                Label(LocalizationManager.shared.localized("revert.unsafe"), systemImage: "exclamationmark.triangle.fill")
                    .font(AppFont.body(weight: .semibold))
                    .foregroundStyle(.orange)
            }
        case .blocked:
            Label(LocalizationManager.shared.localized("revert.unsafe"), systemImage: "exclamationmark.triangle.fill")
                .font(AppFont.body(weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    private func errorCard(_ errorMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizationManager.shared.localized("revert.error"))
                .font(AppFont.body(weight: .semibold))
                .foregroundStyle(.primary)
            Text(errorMessage)
                .font(AppFont.body())
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.red.opacity(0.08))
        )
    }

    private func issueSection(title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppFont.mono(.caption))
                .foregroundStyle(.secondary)
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(AppFont.body())
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
