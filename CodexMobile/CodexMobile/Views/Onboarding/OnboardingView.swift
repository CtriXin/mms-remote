// FILE: OnboardingView.swift
// Purpose: Split onboarding flow — swipeable pages with fixed bottom bar.
// Layer: View
// Exports: OnboardingView
// Depends on: SwiftUI, OnboardingWelcomePage, OnboardingFeaturesPage, OnboardingStepPage

import SwiftUI

struct OnboardingView: View {
    let onScanQRCode: () -> Void
    let onPairWithCode: () -> Void
    @State private var currentPage = 0
    @State private var isShowingCodexInstallReminder = false

    private let pageCount = 5
    private let codexInstallStepIndex = 2
    private let codexInstallCommand = "npm install -g @openai/codex@latest"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    OnboardingWelcomePage()
                        .tag(0)

                    OnboardingFeaturesPage()
                        .tag(1)

                    OnboardingStepPage(
                        stepNumber: 1,
                        icon: "terminal",
                        title: LocalizationManager.shared.localized("onboarding.step1.title"),
                        description: LocalizationManager.shared.localized("onboarding.step1.desc"),
                        command: codexInstallCommand
                    )
                    .tag(2)

                    OnboardingStepPage(
                        stepNumber: 2,
                        icon: "link",
                        title: LocalizationManager.shared.localized("onboarding.step2.title"),
                        description: LocalizationManager.shared.localized("onboarding.step2.desc"),
                        command: "npm install -g mms-remote@latest",
                        commandCaption: LocalizationManager.shared.localized("onboarding.step2.caption")
                    )
                    .tag(3)

                    OnboardingStepPage(
                        stepNumber: 3,
                        icon: "qrcode.viewfinder",
                        title: LocalizationManager.shared.localized("onboarding.step3.title"),
                        description: LocalizationManager.shared.localized("onboarding.step3.desc"),
                        command: "mms-remote up"
                    )
                    .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                bottomBar
            }
        }
        .preferredColorScheme(.dark)
        .alert(LocalizationManager.shared.localized("onboarding.alert.title"), isPresented: $isShowingCodexInstallReminder) {
            Button(LocalizationManager.shared.localized("onboarding.stay"), role: .cancel) {}
            Button(LocalizationManager.shared.localized("onboarding.continue")) {
                advanceToNextPage()
            }
        } message: {
            Text(LocalizationManager.shared.localized("onboarding.alert.message").replacingOccurrences(of: "%@", with: codexInstallCommand))
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 20) {
            // Animated pill dots
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == currentPage ? Color.white : Color.white.opacity(0.18))
                        .frame(width: i == currentPage ? 24 : 8, height: 8)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentPage)

            finalPageActions

            OpenSourceBadge(style: .light)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.6), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 50)
            .offset(y: -50),
            alignment: .top
        )
    }

    // MARK: - State

    @ViewBuilder
    private var finalPageActions: some View {
        if currentPage == pageCount - 1 {
            VStack(spacing: 10) {
                PrimaryCapsuleButton(
                    title: LocalizationManager.shared.localized("onboarding.scan_qr"),
                    systemImage: "qrcode",
                    action: handleContinue
                )

                secondaryCapsuleButton(
                    title: LocalizationManager.shared.localized("onboarding.pair_code"),
                    systemImage: "keyboard",
                    action: onPairWithCode
                )
            }
        } else {
            PrimaryCapsuleButton(
                title: buttonTitle,
                action: handleContinue
            )
        }
    }

    // Offers the first-run manual pairing path without competing visually with the primary QR flow.
    private func secondaryCapsuleButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))

                Text(title)
                    .font(AppFont.body(weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var buttonTitle: String {
        switch currentPage {
        case 0: return LocalizationManager.shared.localized("onboarding.button.get_started")
        case 1: return LocalizationManager.shared.localized("onboarding.button.setup")
        default: return LocalizationManager.shared.localized("onboarding.continue")
        }
    }

    private func handleContinue() {
        // The CLI install step is a hard requirement, so warn before advancing.
        if currentPage == codexInstallStepIndex {
            isShowingCodexInstallReminder = true
            return
        }

        if currentPage < pageCount - 1 {
            advanceToNextPage()
        } else {
            onScanQRCode()
        }
    }

    private func advanceToNextPage() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentPage += 1
        }
    }
}

// MARK: - Previews

#Preview("Full Flow") {
    OnboardingView(
        onScanQRCode: {
            print("Scan tapped")
        },
        onPairWithCode: {
            print("Code tapped")
        }
    )
}

#Preview("Light Override") {
    OnboardingView(
        onScanQRCode: {
            print("Scan tapped")
        },
        onPairWithCode: {
            print("Code tapped")
        }
    )
    .preferredColorScheme(.light)
}
