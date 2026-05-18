// FILE: WhatsNewSheet.swift
// Purpose: Lightweight root sheet that summarizes one release's notable improvements.
// Layer: View
// Exports: WhatsNewSheet
// Depends on: SwiftUI, AppFont

import SwiftUI

private let whatsNewItems: [String] = (1...20).map { LocalizationManager.shared.localized("whatsnew.\($0)") }

struct WhatsNewSheet: View {
    let version: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        header
                        featureList
                        visibilityNote
                    }
                    .padding(24)
                    .padding(.bottom, 140)
                }

                pinnedDismissButton
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized: "whatsnew.title")
                .font(AppFont.title2(weight: .bold))

            Text("MMS Remote \(version)")
                .font(AppFont.mono(.subheadline))
                .foregroundStyle(.secondary)

            Text(localized: "whatsnew.subtitle")
                .font(AppFont.body())
                .foregroundStyle(.secondary)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(whatsNewItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    Text(.init(item))
                        .font(AppFont.body())
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visibilityNote: some View {
        Text(localized: "whatsnew.note")
            .font(AppFont.caption())
            .foregroundStyle(.secondary)
    }

    private var pinnedDismissButton: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    Color(.systemBackground).opacity(0),
                    Color(.systemBackground).opacity(0.92),
                    Color(.systemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 64)
            .allowsHitTesting(false)

            PrimaryCapsuleButton(title: LocalizationManager.shared.localized("whatsnew.button.got_it")) {
                onDismiss()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .background(Color(.systemBackground))
        }
    }
}
