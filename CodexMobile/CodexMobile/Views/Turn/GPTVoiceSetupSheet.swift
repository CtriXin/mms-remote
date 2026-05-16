// FILE: GPTVoiceSetupSheet.swift
// Purpose: Shows a compact info sheet that explains how MMS Remote voice uses the paired computer's ChatGPT session.
// Layer: View
// Exports: GPTVoiceSetupSheet
// Depends on: SwiftUI, AppFont

import SwiftUI

struct GPTVoiceSetupSheet: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.08))
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localized: "voice.setup.header")
                            .font(AppFont.subheadline(weight: .semibold))
                        Text(localized: "voice.setup.subtitle")
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    infoStep(
                        number: "1",
                        title: LocalizationManager.shared.localized("voice.step.1.title"),
                        detail: LocalizationManager.shared.localized("voice.step.1.detail")
                    )
                    infoStep(
                        number: "2",
                        title: LocalizationManager.shared.localized("voice.step.2.title"),
                        detail: LocalizationManager.shared.localized("voice.step.2.detail")
                    )
                    infoStep(
                        number: "3",
                        title: LocalizationManager.shared.localized("voice.step.3.title"),
                        detail: LocalizationManager.shared.localized("voice.step.3.detail")
                    )
                    infoStep(
                        number: "4",
                        title: LocalizationManager.shared.localized("voice.step.4.title"),
                        detail: LocalizationManager.shared.localized("voice.step.4.detail")
                    )
                }

                Text(localized: "voice.setup.summary")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .padding(20)
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .navigationTitle(LocalizationManager.shared.localized("voice.setup.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // Keeps the voice flow easy to scan in a compact informational sheet.
    private func infoStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
