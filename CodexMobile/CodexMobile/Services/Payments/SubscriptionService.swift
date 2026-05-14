// FILE: SubscriptionService.swift
// Purpose: Local-first source builds run without an App Store subscription gate.
// Layer: Service
// Exports: SubscriptionService, SubscriptionPackageOption
// Depends on: Foundation, Observation

import Foundation
import Observation

enum SubscriptionBootstrapState: Equatable {
    case idle
    case loading
    case ready
    case failed
}

struct SubscriptionPackageOption: Identifiable, Equatable {
    let id: String
    let title: String
    let price: String
    let periodLabel: String
    let termsDescription: String
    let isLifetime: Bool
    let callToActionTitle: String
    let footerDescription: String
}

@MainActor
@Observable
final class SubscriptionService {
    private(set) var bootstrapState: SubscriptionBootstrapState = .ready
    private(set) var packageOptions: [SubscriptionPackageOption] = []
    private(set) var hasProAccess = true
    private(set) var freeSendCount = 0
    private(set) var latestPurchaseDate: Date?
    private(set) var willRenew = false
    private(set) var managementURL: URL?
    private(set) var isLoading = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var lastErrorMessage: String?

    init(defaults _: UserDefaults = .standard) {}

    var remainingFreeSendAttempts: Int { Int.max }
    var hasFreeSendAccess: Bool { true }
    var hasAppAccess: Bool { true }

    func consumeFreeSendAttemptIfNeeded() {}

    func bootstrap() async {
        bootstrapState = .ready
        hasProAccess = true
        isLoading = false
        lastErrorMessage = nil
    }

    func refreshCustomerInfoSilently() async {}

    func loadOfferings() async {
        packageOptions = []
        isLoading = false
        lastErrorMessage = nil
    }

    func purchase(_: SubscriptionPackageOption) async {
        hasProAccess = true
        isPurchasing = false
        lastErrorMessage = nil
    }

    func restorePurchases() async {
        hasProAccess = true
        isRestoring = false
        lastErrorMessage = nil
    }

    func syncPurchasesAfterOfferCodeRedemption() async {
        hasProAccess = true
        lastErrorMessage = nil
    }
}
