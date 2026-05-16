// FILE: TurnGitActionsToolbar.swift
// Purpose: Encapsulates Git actions toolbar UI for bridge-triggered git operations.
// Layer: View Component
// Exports: TurnGitActionsToolbarButton
// Depends on: SwiftUI, GitActionModels

import SwiftUI

extension TurnGitActionKind {
    func menuIcon(pointSize: CGFloat = 20) -> UIImage {
        let cgSize = CGSize(width: pointSize, height: pointSize)
        switch self {
        case .initialize:
            return Self.resizedSymbol(named: "plus.circle", size: cgSize)
        case .syncNow:
            return Self.resizedSymbol(named: "arrow.trianglehead.2.clockwise.rotate.90", size: cgSize)
        case .commit:
            return Self.resizedAsset(named: "git-commit", size: cgSize)
        case .push:
            return Self.resizedSymbol(named: "arrow.up.circle", size: cgSize)
        case .commitAndPush:
            return Self.resizedAsset(named: "cloud-upload", size: cgSize)
        case .commitPushCreatePR:
            return Self.resizedAsset(named: "GitHub_Invertocat_Black", size: cgSize)
        case .createPR:
            return Self.resizedAsset(named: "GitHub_Invertocat_Black", size: cgSize)
        case .discardRuntimeChangesAndSync:
            return Self.resizedSymbol(named: "trash.circle", size: cgSize)
        }
    }

    private static func resizedAsset(named name: String, size: CGSize) -> UIImage {
        guard let original = UIImage(named: name)?.withRenderingMode(.alwaysTemplate) else {
            return UIImage()
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            original.draw(in: CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysTemplate)
    }

    private static func resizedSymbol(named name: String, size: CGSize) -> UIImage {
        let config = UIImage.SymbolConfiguration(pointSize: size.height, weight: .regular)
        guard let symbol = UIImage(systemName: name, withConfiguration: config)?.withRenderingMode(.alwaysTemplate) else {
            return UIImage()
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        let scale = min(size.width / symbol.size.width, size.height / symbol.size.height)
        let scaled = CGSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
        let origin = CGPoint(x: (size.width - scaled.width) / 2, y: (size.height - scaled.height) / 2)
        return renderer.image { _ in
            symbol.draw(in: CGRect(origin: origin, size: scaled))
        }.withRenderingMode(.alwaysTemplate)
    }
}

struct TurnGitActionsToolbarButton: View {
    let isEnabled: Bool
    let disabledActions: Set<TurnGitActionKind>
    let isRunningAction: Bool
    let loadingTitle: String?
    let showsDiscardRuntimeChangesAndSync: Bool
    let gitSyncState: String?
    let onSelect: (TurnGitActionKind) -> Void

    private let minToolbarButtonSize: CGFloat = 28

    private var syncStatusColor: Color? {
        switch gitSyncState {
        case "not_initialized":
            return Color(.systemOrange)
        case "behind_only", "diverged", "dirty_and_behind":
            return Color(.systemGray2)
        default:
            return nil
        }
    }

    private var syncStatusAccessibilityValue: String? {
        switch gitSyncState {
        case "not_initialized":
            return LocalizationManager.shared.localized("git.not_initialized")
        case "up_to_date":
            return LocalizationManager.shared.localized("git.up_to_date")
        case "ahead_only":
            return LocalizationManager.shared.localized("git.ahead")
        case "behind_only":
            return LocalizationManager.shared.localized("git.behind")
        case "diverged":
            return LocalizationManager.shared.localized("git.diverged")
        case "dirty":
            return LocalizationManager.shared.localized("git.dirty")
        case "dirty_and_behind":
            return LocalizationManager.shared.localized("git.dirty_and_behind")
        case "no_upstream":
            return LocalizationManager.shared.localized("git.no_upstream")
        case "detached_head":
            return LocalizationManager.shared.localized("git.detached")
        default:
            return nil
        }
    }

    var body: some View {
        Menu {
            if gitSyncState == "not_initialized" {
                Section(LocalizationManager.shared.localized("git.setup")) {
                    actionButton(for: .initialize)
                }
            } else {
                Section(LocalizationManager.shared.localized("git.update")) {
                    actionButton(for: .syncNow)
                }

                Section(LocalizationManager.shared.localized("git.write")) {
                    ForEach([TurnGitActionKind.commit, .push, .commitAndPush, .commitPushCreatePR, .createPR], id: \.self) { action in
                        actionButton(for: action)
                    }
                }

                if !recoveryActions.isEmpty {
                    Section(LocalizationManager.shared.localized("git.recovery")) {
                        ForEach(recoveryActions, id: \.self) { action in
                            actionButton(for: action)
                        }
                    }
                }
            }
        } label: {
            toolbarIcon(for: gitSyncState == "not_initialized" ? .initialize : .commit, size: 24)
                .overlay(alignment: .topTrailing) {
                    // Skip the dot while a git action runs; the in-app toast already shows live progress.
                    if !isRunningAction, let syncStatusColor {
                        Circle()
                            .fill(syncStatusColor)
                            .frame(width: 8, height: 8)
                            .overlay {
                                Circle()
                                    .stroke(Color(.systemBackground), lineWidth: 1.5)
                            }
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .controlSize(.small)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
        .frame(minWidth: minToolbarButtonSize, minHeight: minToolbarButtonSize)
        .contentShape(Circle())
        .adaptiveToolbarItem(in: Circle())
        .accessibilityLabel(LocalizationManager.shared.localized("git.actions"))
        .accessibilityValue(loadingTitle ?? syncStatusAccessibilityValue ?? LocalizationManager.shared.localized("git.status_unavailable"))
    }

    private var recoveryActions: [TurnGitActionKind] {
        showsDiscardRuntimeChangesAndSync ? [.discardRuntimeChangesAndSync] : []
    }

    private func actionButton(for action: TurnGitActionKind) -> some View {
        Button {
            HapticFeedback.shared.triggerImpactFeedback()
            onSelect(action)
        } label: {
            Label {
                Text(action.title)
            } icon: {
                Image(uiImage: action.menuIcon())
            }
        }
        .disabled(!isEnabled || disabledActions.contains(action))
    }

    @ViewBuilder
    private func toolbarIcon(for action: TurnGitActionKind, size: CGFloat) -> some View {
        Image(uiImage: action.menuIcon(pointSize: size))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(.primary)
            .frame(width: size, height: size)
    }
}
