// FILE: SidebarHeaderView.swift
// Purpose: Displays the sidebar app identity header and the inline close affordance for full-width presentation.
// Layer: View Component
// Exports: SidebarHeaderView

import SwiftUI

struct SidebarHeaderView: View {
    var showsCloseButton = false
    var showsSelectionButton = false
    var isSelectionMode = false
    var onClose: () -> Void = {}
    var onSelectionModeToggle: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(localized: "sidebar.title")
                .font(AppFont.title3(weight: .medium))

            Spacer(minLength: 0)

            if showsSelectionButton {
                Button(action: onSelectionModeToggle) {
                    Text(LocalizationManager.shared.localized(isSelectionMode ? "sidebar.done" : "sidebar.select"))
                        .font(AppFont.subheadline(weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizationManager.shared.localized(isSelectionMode ? "sidebar.done" : "sidebar.select"))
            }

            if showsCloseButton {
                // Mirrors the top-bar menu affordance so full-width sidebar presentations still
                // have an obvious close target after the content shifts completely offscreen.
                Button(action: onClose) {
                    TwoLineHamburgerIcon()
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .adaptiveGlass(.regular, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizationManager.shared.localized("sidebar.close_menu"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

#Preview {
    SidebarHeaderView(showsCloseButton: true)
}
