// FILE: OnboardingFeaturesPage.swift
// Purpose: Compact feature highlights page shown after the welcome splash.
// Layer: View
// Exports: OnboardingFeaturesPage
// Depends on: SwiftUI, AppFont

import SwiftUI

struct OnboardingFeaturesPage: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 40) {
                VStack(spacing: 10) {
                    Text(LocalizationManager.shared.localized("onboarding.features.title"))
                        .font(AppFont.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Text(LocalizationManager.shared.localized("onboarding.features.subtitle"))
                        .font(AppFont.subheadline())
                        .foregroundStyle(.white.opacity(0.45))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                VStack(spacing: 16) {
                    featureRow(
                        icon: "hare.fill",
                        color: .yellow,
                        title: LocalizationManager.shared.localized("onboarding.features.fast.title"),
                        subtitle: LocalizationManager.shared.localized("onboarding.features.fast.subtitle")
                    )
                    featureRow(
                        icon: "arrow.triangle.branch",
                        color: .green,
                        title: LocalizationManager.shared.localized("onboarding.features.git.title"),
                        subtitle: LocalizationManager.shared.localized("onboarding.features.git.subtitle")
                    )
                    featureRow(
                        icon: "lock.shield.fill",
                        color: .cyan,
                        title: LocalizationManager.shared.localized("onboarding.features.e2ee.title"),
                        subtitle: LocalizationManager.shared.localized("onboarding.features.e2ee.subtitle")
                    )
                    featureRow(
                        icon: "waveform",
                        color: .purple,
                        title: LocalizationManager.shared.localized("onboarding.features.voice.title"),
                        subtitle: LocalizationManager.shared.localized("onboarding.features.voice.subtitle")
                    )
                    featureRow(
                        icon: "point.3.connected.trianglepath.dotted",
                        color: .orange,
                        title: LocalizationManager.shared.localized("onboarding.features.subagents.title"),
                        subtitle: LocalizationManager.shared.localized("onboarding.features.subagents.subtitle")
                    )
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    @ViewBuilder
    private func featureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(AppFont.caption())
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        OnboardingFeaturesPage()
    }
    .preferredColorScheme(.dark)
}
