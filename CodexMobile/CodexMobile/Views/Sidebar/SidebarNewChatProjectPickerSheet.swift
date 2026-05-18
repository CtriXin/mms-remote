// FILE: SidebarNewChatProjectPickerSheet.swift
// Purpose: Minimal "Start new chat" sheet that lets the user pick a project, worktree, or cloud chat.
// Layer: View
// Exports: SidebarNewChatProjectPickerSheet
// Depends on: SidebarProjectChoice, AppFont, CodexWorktreeIcon

import SwiftUI

struct SidebarNewChatProjectPickerSheet: View {
    let choices: [SidebarProjectChoice]
    let onSelectProject: (String) -> Void
    let onSelectWorktreeProject: (String) -> Void
    let onSelectWithoutProject: () -> Void
    let onBrowseLocalFolder: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onBrowseLocalFolder()
                    } label: {
                        projectRow(
                            icon: AnyView(
                                Image(systemName: "folder.badge.plus")
                                    .font(AppFont.body(weight: .medium))
                                    .foregroundStyle(.secondary)
                            ),
                            title: LocalizationManager.shared.localized("picker.add_local"),
                            subtitle: LocalizationManager.shared.localized("picker.add_local_hint")
                        )
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text(localized: "picker.header")
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }

                if !choices.isEmpty {
                    Section(LocalizationManager.shared.localized("picker.section.local")) {
                        ForEach(choices) { choice in
                            Button {
                                dismiss()
                                onSelectProject(choice.projectPath)
                            } label: {
                                projectRow(
                                    icon: AnyView(
                                        Group {
                                            if choice.iconSystemName == "arrow.triangle.branch" {
                                                CodexWorktreeIcon(pointSize: 16, weight: .medium)
                                            } else {
                                                Image(systemName: choice.iconSystemName)
                                                    .font(AppFont.body(weight: .medium))
                                            }
                                        }
                                        .foregroundStyle(.secondary)
                                    ),
                                    title: choice.label,
                                    subtitle: nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Section(LocalizationManager.shared.localized("picker.section.worktree")) {
                        ForEach(choices) { choice in
                            Button {
                                dismiss()
                                onSelectWorktreeProject(choice.projectPath)
                            } label: {
                                projectRow(
                                    icon: AnyView(
                                        CodexWorktreeIcon(pointSize: 16, weight: .medium)
                                            .foregroundStyle(.secondary)
                                    ),
                                    title: choice.label,
                                    subtitle: LocalizationManager.shared.localized("sidebar.detached_worktree")
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button {
                        dismiss()
                        onSelectWithoutProject()
                    } label: {
                        projectRow(
                            icon: AnyView(
                                Image(systemName: "cloud")
                                    .font(AppFont.body(weight: .medium))
                                    .foregroundStyle(.secondary)
                            ),
                            title: LocalizationManager.shared.localized("picker.cloud"),
                            subtitle: LocalizationManager.shared.localized("picker.cloud_hint")
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .navigationTitle(LocalizationManager.shared.localized("picker.nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizationManager.shared.localized("picker.button.close")) {
                        dismiss()
                    }
                    .tint(.secondary)
                }
            }
        }
        .presentationDetents(choices.count > 4 ? [.fraction(0.75), .large] : [.fraction(0.75)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func projectRow(icon: AnyView, title: String, subtitle: String?) -> some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: 12) {
            icon
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.body(weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let subtitle {
                    Text(subtitle)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Image(systemName: "chevron.right")
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Previews

#if DEBUG
private enum SidebarNewChatProjectPickerSheetPreviewData {
    static let sampleChoices: [SidebarProjectChoice] = [
        SidebarProjectChoice(
            id: "dpcode-website",
            label: "dpcode-website",
            iconSystemName: "laptopcomputer",
            projectPath: "/Users/demo/Developer/dpcode-website",
            sortDate: Date()
        ),
        SidebarProjectChoice(
            id: "openusage",
            label: "openusage",
            iconSystemName: "laptopcomputer",
            projectPath: "/Users/demo/Developer/openusage",
            sortDate: Date()
        ),
        SidebarProjectChoice(
            id: "MMS Remote",
            label: "MMS Remote",
            iconSystemName: "laptopcomputer",
            projectPath: "/Users/demo/Developer/MMS Remote",
            sortDate: Date()
        )
    ]
}

#Preview("Light") {
    Color.gray.opacity(0.15).ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            SidebarNewChatProjectPickerSheet(
                choices: SidebarNewChatProjectPickerSheetPreviewData.sampleChoices,
                onSelectProject: { _ in },
                onSelectWorktreeProject: { _ in },
                onSelectWithoutProject: {},
                onBrowseLocalFolder: {}
            )
        }
}

#Preview("Dark") {
    Color.gray.opacity(0.15).ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            SidebarNewChatProjectPickerSheet(
                choices: SidebarNewChatProjectPickerSheetPreviewData.sampleChoices,
                onSelectProject: { _ in },
                onSelectWorktreeProject: { _ in },
                onSelectWithoutProject: {},
                onBrowseLocalFolder: {}
            )
        }
        .preferredColorScheme(.dark)
}

#Preview("Empty") {
    Color.gray.opacity(0.15).ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            SidebarNewChatProjectPickerSheet(
                choices: [],
                onSelectProject: { _ in },
                onSelectWorktreeProject: { _ in },
                onSelectWithoutProject: {},
                onBrowseLocalFolder: {}
            )
        }
}
#endif
