// FILE: SettingsView.swift
// Purpose: Settings for Local Mode (Codex runs on the paired computer, relay WebSocket).
// Layer: View
// Exports: SettingsView

import SwiftUI
import StoreKit
import UIKit

struct SettingsView: View {
    @AppStorage("codex.appFontStyle") private var appFontStyleRawValue = AppFont.defaultStoredStyleRawValue

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                SettingsArchivedChatsCard()
                SettingsAppearanceCard(appFontStyle: appFontStyleBinding)
                SettingsLanguageCard()
                SettingsNotificationsCard()
                SettingsGPTAccountCard()
                SettingsSubscriptionCard()
                SettingsAppVersionCard()
                SettingsBridgeVersionCard()
                SettingsRuntimeDefaultsCard()
                SettingsAboutCard()
                SettingsUsageCard()
                SettingsConnectionCard()
            }
            .padding()
        }
        .font(AppFont.body())
        .navigationTitle(Text(localized: "settings.title"))
    }

    private var appFontStyleBinding: Binding<AppFont.Style> {
        Binding(
            get: { AppFont.Style(rawValue: appFontStyleRawValue) ?? AppFont.defaultStyle },
            set: { appFontStyleRawValue = $0.rawValue }
        )
    }
}

private struct SettingsRuntimeDefaultsCard: View {
    @Environment(CodexService.self) private var codex

    private let runtimeAutoValue = "__AUTO__"
    private let runtimeNormalValue = "__NORMAL__"
    private let settingsAccentColor = Color(.plan)

    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.runtime_defaults")) {
            HStack {
                Text(localized: "settings.model")
                Spacer()
                Picker("Model", selection: runtimeModelSelection) {
                    Text(localized: "settings.auto").tag(runtimeAutoValue)
                    ForEach(runtimeModelOptions, id: \.id) { model in
                        Text(TurnComposerMetaMapper.modelTitle(for: model))
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }

            HStack {
                Text(localized: "settings.reasoning")
                Spacer()
                Picker("Reasoning", selection: runtimeReasoningSelection) {
                    Text(localized: "settings.auto").tag(runtimeAutoValue)
                    ForEach(runtimeReasoningOptions, id: \.id) { option in
                        Text(option.title).tag(option.effort)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
                .disabled(runtimeReasoningOptions.isEmpty)
            }

            if codex.selectedModelSupportsServiceTier(.fast) {
                HStack {
                    Text(localized: "settings.speed")
                    Spacer()
                    Picker("Speed", selection: runtimeServiceTierSelection) {
                        Text(localized: "settings.normal").tag(runtimeNormalValue)
                        ForEach(CodexServiceTier.allCases, id: \.rawValue) { tier in
                            Text(tier.displayName).tag(tier.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(settingsAccentColor)
                }
            }

            HStack {
                Text(localized: "settings.access")
                Spacer()
                Picker("Access", selection: runtimeAccessSelection) {
                    ForEach(CodexAccessMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }

            Divider()

            HStack {
                Text(localized: "settings.git_writer_model")
                Spacer()
                Picker("Git writer model", selection: gitWriterModelSelection) {
                    ForEach(gitWriterModelOptions, id: \.id) { model in
                        Text(TurnComposerMetaMapper.modelTitle(for: model))
                            .tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
                .disabled(gitWriterModelOptions.isEmpty)
            }

            Text(localized: "settings.git_writer_hint")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
        }
    }

    private var runtimeModelOptions: [CodexModelOption] {
        TurnComposerMetaMapper.orderedModels(from: codex.availableModels)
    }

    private var runtimeReasoningOptions: [TurnComposerReasoningDisplayOption] {
        TurnComposerMetaMapper.reasoningDisplayOptions(
            from: codex.supportedReasoningEffortsForSelectedModel().map(\.reasoningEffort)
        )
    }

    private var runtimeModelSelection: Binding<String> {
        Binding(
            get: { codex.selectedModelOption()?.id ?? runtimeAutoValue },
            set: { selection in
                codex.setSelectedModelId(selection == runtimeAutoValue ? nil : selection)
            }
        )
    }

    private var runtimeReasoningSelection: Binding<String> {
        Binding(
            get: { codex.selectedReasoningEffort ?? runtimeAutoValue },
            set: { selection in
                codex.setSelectedReasoningEffort(selection == runtimeAutoValue ? nil : selection)
            }
        )
    }

    private var runtimeAccessSelection: Binding<CodexAccessMode> {
        Binding(
            get: { codex.selectedAccessMode },
            set: { codex.setSelectedAccessMode($0) }
        )
    }

    private var runtimeServiceTierSelection: Binding<String> {
        Binding(
            get: { codex.selectedServiceTier?.rawValue ?? runtimeNormalValue },
            set: { selection in
                codex.setSelectedServiceTier(
                    selection == runtimeNormalValue ? nil : CodexServiceTier(rawValue: selection)
                )
            }
        )
    }

    private var gitWriterModelOptions: [CodexModelOption] {
        TurnComposerMetaMapper.orderedModels(from: codex.availableModels)
    }

    private var gitWriterModelSelection: Binding<String> {
        Binding(
            get: { codex.selectedGitWriterModelOption()?.id ?? gitWriterModelOptions.first?.id ?? "" },
            set: { codex.setSelectedGitWriterModelId($0.isEmpty ? nil : $0) }
        )
    }
}

private struct SettingsConnectionCard: View {
    @Environment(CodexService.self) private var codex
    @State private var isShowingComputerNameSheet = false

    private let settingsAccentColor = Color(.plan)

    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.connection")) {
            if let trustedPairPresentation = codex.trustedPairPresentation {
                SettingsTrustedComputerCard(
                    presentation: trustedPairPresentation,
                    connectionStatusLabel: connectionStatusLabel,
                    onEditName: {
                        isShowingComputerNameSheet = true
                    }
                )
            } else {
                Text(localized: "settings.no_paired_computer")
                    .font(AppFont.subheadline(weight: .semibold))
                    .foregroundStyle(.primary)
            }

            if connectionPhaseShowsProgress {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(connectionProgressLabel)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }
            }

            if case .retrying(_, let message) = codex.connectionRecoveryState,
               !message.isEmpty {
                Text(message)
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
            }

            if let error = codex.lastErrorMessage, !error.isEmpty {
                Text(error)
                    .font(AppFont.caption())
                    .foregroundStyle(.red)
            }

            Divider()

            if codex.supportsKeepAwakeWhileBridgeRuns {
                Toggle(LocalizationManager.shared.localized("settings.keep_awake"), isOn: keepMacAwakeWhileBridgeRunsBinding)
                    .tint(settingsAccentColor)

                Text(codex.keepMacAwakeWhileBridgeRuns
                     ? LocalizationManager.shared.localized("settings.keep_awake_hint")
                     : LocalizationManager.shared.localized("settings.keep_awake_idle_hint"))
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)

                if !codex.isConnected {
                    Text(localized: "settings.saved_on_iphone")
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }
            }

            if codex.isConnected {
                SettingsButton(LocalizationManager.shared.localized("settings.disconnect"), role: .destructive) {
                    HapticFeedback.shared.triggerImpactFeedback()
                    disconnectRelay()
                }
            } else if codex.hasTrustedMacReconnectCandidate {
                SettingsButton(LocalizationManager.shared.localized("settings.forget_pair"), role: .destructive) {
                    HapticFeedback.shared.triggerImpactFeedback()
                    codex.forgetTrustedMac()
                }
            }
        }
        .sheet(isPresented: $isShowingComputerNameSheet) {
            if let trustedPairPresentation = codex.trustedPairPresentation {
                SettingsComputerNameSheet(
                    nickname: sidebarComputerNicknameBinding(for: trustedPairPresentation),
                    currentName: trustedPairPresentation.name,
                    systemName: trustedPairPresentation.systemName ?? trustedPairPresentation.name
                )
            }
        }
    }

    private var keepMacAwakeWhileBridgeRunsBinding: Binding<Bool> {
        Binding(
            get: { codex.keepMacAwakeWhileBridgeRuns },
            set: { nextValue in
                codex.setKeepMacAwakeWhileBridgeRunsPreference(nextValue)
                Task { @MainActor in
                    await codex.syncBridgeKeepMacAwakePreferenceIfNeeded(showFailureInUI: true)
                }
            }
        )
    }

    private var connectionPhaseShowsProgress: Bool {
        switch codex.connectionPhase {
        case .connecting, .loadingChats, .syncing:
            return true
        case .offline, .connected:
            return false
        }
    }

    private var connectionStatusLabel: String {
        let lm = LocalizationManager.shared
        switch codex.connectionPhase {
        case .offline:
            return lm.localized("connection.offline")
        case .connecting:
            return lm.localized("connection.connecting")
        case .loadingChats:
            return lm.localized("connection.loading_chats")
        case .syncing:
            return lm.localized("connection.syncing")
        case .connected:
            return lm.localized("connection.connected")
        }
    }

    private var connectionProgressLabel: String {
        let lm = LocalizationManager.shared
        switch codex.connectionPhase {
        case .connecting:
            return lm.localized("connection.connecting_relay")
        case .loadingChats:
            return lm.localized("connection.loading_chats_progress")
        case .syncing:
            return lm.localized("connection.syncing_workspace")
        case .offline, .connected:
            return ""
        }
    }

    // MARK: - Actions

    private func disconnectRelay() {
        Task { @MainActor in
            await codex.disconnect()
            codex.clearSavedRelaySession()
        }
    }

    // Writes nicknames against the active trusted computer so switching pairs does not reuse the wrong alias.
    private func sidebarComputerNicknameBinding(for presentation: CodexTrustedPairPresentation) -> Binding<String> {
        Binding(
            get: { SidebarComputerNicknameStore.nickname(for: presentation.deviceId) },
            set: { SidebarComputerNicknameStore.setNickname($0, for: presentation.deviceId) }
        )
    }
}

private struct SettingsSubscriptionCard: View {
    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.access")) {
            HStack {
                Text(localized: "settings.status")
                Spacer()
                Text(localized: "settings.local_build")
                    .foregroundStyle(.green)
            }

            Text(localized: "settings.local_build_hint")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Reusable card / button components

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }
}

struct SettingsButton: View {
    let title: String
    var role: ButtonRole?
    var isLoading: Bool = false
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    Text(title)
                }
            }
            .font(AppFont.subheadline(weight: .medium))
            .foregroundStyle(role == .destructive ? .red : (role == .cancel ? .secondary : .primary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                (role == .destructive ? Color.red : Color.primary).opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Extracted independent section views

private struct SettingsUsageCard: View {
    @Environment(CodexService.self) private var codex
    @Environment(\.scenePhase) private var scenePhase

    @State private var isRefreshing = false

    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.usage")) {
            UsageStatusSummaryContent(
                contextWindowUsage: nil,
                showsContextWindowSection: false,
                rateLimitBuckets: codex.rateLimitBuckets,
                isLoadingRateLimits: codex.isLoadingRateLimits,
                rateLimitsErrorMessage: codex.rateLimitsErrorMessage,
                refreshControl: UsageStatusRefreshControl(
                    title: LocalizationManager.shared.localized("button.refresh"),
                    isRefreshing: isRefreshing,
                    action: refreshStatus
                )
            )
        }
        .task {
            await refreshStatusIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshStatusIfNeeded()
            }
        }
    }

    private func refreshStatus() {
        guard !isRefreshing else { return }
        HapticFeedback.shared.triggerImpactFeedback(style: .light)
        isRefreshing = true

        Task {
            await refreshStatusData()
            await MainActor.run {
                isRefreshing = false
            }
        }
    }

    private func refreshStatusIfNeeded() async {
        guard !isRefreshing else { return }
        guard codex.shouldAutoRefreshUsageStatus(threadId: nil) else { return }

        await MainActor.run {
            isRefreshing = true
        }
        await refreshStatusData()
        await MainActor.run {
            isRefreshing = false
        }
    }

    // Settings only needs the account-wide usage windows.
    private func refreshStatusData() async {
        await codex.refreshUsageStatus(threadId: nil)
    }
}

private struct SettingsLanguageCard: View {
    @State private var languageRefreshToken = UUID()

    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.language")) {
            HStack {
                Text(LocalizationManager.shared.localized("settings.language"))
                Spacer()
                Picker("Language", selection: Binding(
                    get: { LocalizationManager.shared.currentLanguage },
                    set: { LocalizationManager.shared.currentLanguage = $0 }
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
        .id(languageRefreshToken)
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            languageRefreshToken = UUID()
        }
    }
}

private struct SettingsAppearanceCard: View {
    @Binding var appFontStyle: AppFont.Style
    @AppStorage("codex.useLiquidGlass") private var useLiquidGlass = true
    @AppStorage(UserBubbleColor.storageKey) private var userBubbleColorRawValue = UserBubbleColor.defaultStoredRawValue
    private let settingsAccentColor = Color(.plan)

    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.appearance")) {
            HStack {
                Text(localized: "settings.font")
                Spacer()
                Picker("Font", selection: $appFontStyle) {
                    ForEach(AppFont.Style.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .tint(settingsAccentColor)
            }

            Divider()

            HStack {
                Text(localized: "settings.message_bubble")
                Menu {
                    ForEach(UserBubbleColor.allCases) { color in
                        Button {
                            userBubbleColorRawValue = color.rawValue
                        } label: {
                            Label {
                                Text(color.title)
                            } icon: {
                                Image(uiImage: color.menuSwatchImage)
                                    .renderingMode(.original)
                            }
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(selectedUserBubbleColor.swatchColor)
                            .frame(width: 14, height: 14)
                    }
                    .frame(maxWidth: .infinity, minHeight: 28, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(LocalizationManager.shared.localized("settings.message_bubble"))
                .accessibilityValue(selectedUserBubbleColor.title)
                .tint(settingsAccentColor)
            }

            if GlassPreference.isSupported {
                Divider()

                Toggle(LocalizationManager.shared.localized("settings.liquid_glass"), isOn: $useLiquidGlass)
                    .tint(settingsAccentColor)
            }

            Divider()

            SettingsPetCompanionSection(settingsAccentColor: settingsAccentColor)
        }
    }

    private var selectedUserBubbleColor: UserBubbleColor {
        UserBubbleColor(rawValue: userBubbleColorRawValue) ?? .default
    }
}

private struct SettingsPetCompanionSection: View {
    @Environment(CodexService.self) private var codex
    @Environment(PetCompanionStore.self) private var petStore

    let settingsAccentColor: Color

    var body: some View {
        Group {
            Toggle(isOn: petEnabledBinding) {
                HStack(spacing: 8) {
                    Text(localized: "settings.companion_pet")
                    Text(localized: "settings.beta")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(settingsAccentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(settingsAccentColor.opacity(0.15))
                        )
                }
            }
            .tint(settingsAccentColor)

            if petStore.isEnabled {
                if petStore.availablePets.isEmpty {
                    Text(petStore.isLoading
                         ? LocalizationManager.shared.localized("pets.loading")
                         : LocalizationManager.shared.localized("pets.not_found"))
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Text(localized: "settings.pet")
                        Spacer()
                        Picker("Pet", selection: selectedPetBinding) {
                            ForEach(petStore.availablePets) { pet in
                                Text(pet.displayName).tag(pet.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .tint(settingsAccentColor)
                    }

                    if let description = petStore.selectedPet?.description,
                       !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(description)
                            .font(AppFont.caption())
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = petStore.errorMessage {
                    Text(errorMessage)
                        .font(AppFont.caption())
                        .foregroundStyle(.red)
                }

                SettingsButton(LocalizationManager.shared.localized("settings.refresh_pets"), isLoading: petStore.isLoading) {
                    HapticFeedback.shared.triggerImpactFeedback(style: .light)
                    Task {
                        await petStore.refreshPets(codex: codex)
                    }
                }
            }
        }
        .task(id: codex.isConnected) {
            guard codex.isConnected, petStore.isEnabled else {
                return
            }
            await petStore.loadPetsIfNeeded(codex: codex)
            await petStore.loadSelectedPet(codex: codex)
        }
    }

    private var petEnabledBinding: Binding<Bool> {
        Binding(
            get: { petStore.isEnabled },
            set: { isEnabled in
                petStore.setEnabled(isEnabled)
                guard isEnabled else {
                    return
                }
                Task {
                    await petStore.loadPetsIfNeeded(codex: codex)
                    await petStore.loadSelectedPet(codex: codex)
                }
            }
        )
    }

    private var selectedPetBinding: Binding<String> {
        Binding(
            get: { petStore.selectedPet?.id ?? "" },
            set: { selectedID in
                petStore.selectPet(id: selectedID.isEmpty ? nil : selectedID)
                Task {
                    await petStore.loadSelectedPet(codex: codex)
                }
            }
        )
    }
}

private struct SettingsNotificationsCard: View {
    @Environment(CodexService.self) private var codex
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.notifications")) {
            HStack(spacing: 10) {
                Image(systemName: "bell.badge")
                    .foregroundStyle(.primary)
                Text(localized: "settings.status")
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(.secondary)
            }

            Text(localized: "settings.notifications_hint")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            if codex.notificationAuthorizationStatus == .notDetermined {
                SettingsButton(LocalizationManager.shared.localized("settings.allow_notifications")) {
                    HapticFeedback.shared.triggerImpactFeedback()
                    Task {
                        await codex.requestNotificationPermission()
                    }
                }
            }

            if codex.notificationAuthorizationStatus == .denied {
                SettingsButton(LocalizationManager.shared.localized("settings.open_ios_settings")) {
                    HapticFeedback.shared.triggerImpactFeedback()
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        .task {
            await codex.refreshManagedNotificationRegistrationState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                return
            }
            Task {
                await codex.refreshManagedNotificationRegistrationState()
            }
        }
    }

    private var statusLabel: String {
        let lm = LocalizationManager.shared
        switch codex.notificationAuthorizationStatus {
        case .authorized: lm.localized("settings.notif_status.authorized")
        case .denied: lm.localized("settings.notif_status.denied")
        case .provisional: lm.localized("settings.notif_status.provisional")
        case .ephemeral: lm.localized("settings.notif_status.ephemeral")
        case .notDetermined: lm.localized("settings.notif_status.not_requested")
        @unknown default: lm.localized("settings.notif_status.unknown")
        }
    }
}

private struct SettingsGPTAccountCard: View {
    @State private var isShowingMacLoginInfo = false

    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.chatgpt_voice_mode")) {
            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                isShowingMacLoginInfo = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(AppFont.subheadline(weight: .medium))
                    Text(localized: "settings.info")
                        .font(AppFont.subheadline(weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $isShowingMacLoginInfo) {
            GPTVoiceSetupSheet()
        }
    }
}

private struct SettingsAppVersionCard: View {
    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.app_version")) {
            HStack(spacing: 10) {
                Text(localized: "settings.current_build")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? LocalizationManager.shared.localized("settings.unknown")
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? LocalizationManager.shared.localized("settings.unknown")
        return "\(version) (\(build))"
    }
}

private struct SettingsBridgeVersionCard: View {
    @Environment(CodexService.self) private var codex
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.bridge_version")) {
            HStack(spacing: 10) {
                Text(localized: "settings.status")
                Spacer()
                SettingsStatusPill(label: versionStatusLabel)
            }

            settingsVersionRow(
                title: LocalizationManager.shared.localized("bridge.version.installed_on_computer"),
                value: installedVersionLabel,
                valueStyle: installedValueStyle
            )

            settingsVersionRow(
                title: LocalizationManager.shared.localized("bridge.version.latest_available"),
                value: latestVersionLabel,
                valueStyle: .primary
            )

            if let guidance = guidanceText {
                Text(guidance)
                    .font(AppFont.caption())
                    .foregroundStyle(guidanceColor)
            }
        }
        .task {
            await codex.refreshBridgeVersionState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await codex.refreshBridgeVersionState()
            }
        }
    }

    private var installedVersionLabel: String {
        normalizedVersion(codex.bridgeInstalledVersion) ?? LocalizationManager.shared.localized("bridge.version.status_unknown")
    }

    private var latestVersionLabel: String {
        normalizedVersion(codex.latestBridgePackageVersion) ?? LocalizationManager.shared.localized("bridge.version.status_unknown")
    }

    private var guidanceText: String? {
        let lm = LocalizationManager.shared
        guard let installedVersion else {
            return lm.localized("bridge.version.connect_first")
        }

        guard let latestVersion else {
            return lm.localized("bridge.version.installed_detected")
        }

        if installedVersion == latestVersion {
            return lm.localized("bridge.version.up_to_date")
        }

        if installedVersion.compare(latestVersion, options: .numeric) == .orderedAscending {
            return lm.localized("bridge.version.newer_available")
        }

        return lm.localized("bridge.version.different_build")
    }

    private var versionStatusLabel: String {
        let lm = LocalizationManager.shared
        guard let installedVersion else {
            return lm.localized("bridge.version.status_unknown")
        }

        guard let latestVersion else {
            return lm.localized("bridge.version.status_installed")
        }

        if installedVersion == latestVersion {
            return lm.localized("bridge.version.status_up_to_date")
        }

        if installedVersion.compare(latestVersion, options: .numeric) == .orderedAscending {
            return lm.localized("bridge.version.status_update_available")
        }

        return lm.localized("bridge.version.status_different_build")
    }

    private var guidanceColor: Color {
        guard let installedVersion,
              let latestVersion,
              installedVersion.compare(latestVersion, options: .numeric) == .orderedAscending else {
            return .secondary
        }

        return .orange
    }

    private var installedValueStyle: Color {
        guard let installedVersion,
              let latestVersion,
              installedVersion.compare(latestVersion, options: .numeric) == .orderedAscending else {
            return .primary
        }

        return .orange
    }

    private var installedVersion: String? {
        normalizedVersion(codex.bridgeInstalledVersion)
    }

    private var latestVersion: String? {
        normalizedVersion(codex.latestBridgePackageVersion)
    }

    private func normalizedVersion(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private func settingsVersionRow(title: String, value: String, valueStyle: Color) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            Text(value)
                .font(AppFont.mono(.subheadline))
                .foregroundStyle(valueStyle)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }
}

private struct SettingsArchivedChatsCard: View {
    @Environment(CodexService.self) private var codex

    private var archivedCount: Int {
        codex.threads.filter { $0.syncState == .archivedLocal }.count
    }

    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.archived_chats")) {
            NavigationLink {
                ArchivedChatsView()
            } label: {
                HStack {
                    Label(LocalizationManager.shared.localized("settings.archived_chats"), systemImage: "archivebox")
                        .font(AppFont.subheadline(weight: .medium))
                    Spacer()
                    if archivedCount > 0 {
                        Text("\(archivedCount)")
                            .font(AppFont.caption(weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SettingsAboutCard: View {
    @State private var isShowingAbout = false

    var body: some View {
        SettingsCard(title: LocalizationManager.shared.localized("settings.about")) {
            Text(localized: "settings.security_hint")
                .font(AppFont.caption())
                .foregroundStyle(.secondary)

            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                isShowingAbout = true
            } label: {
                settingsAccessoryRow(
                    title: LocalizationManager.shared.localized("settings.how_it_works"),
                    leading: {
                        Image(systemName: "info.circle")
                            .font(AppFont.subheadline(weight: .medium))
                    }
                )
            }
            .buttonStyle(.plain)

            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                UIApplication.shared.open(AppEnvironment.feedbackMailtoURL)
            } label: {
                settingsAccessoryRow(
                    title: LocalizationManager.shared.localized("settings.send_feedback"),
                    leading: {
                        Image(systemName: "envelope")
                            .font(AppFont.subheadline(weight: .medium))
                    }
                )
            }
            .buttonStyle(.plain)

            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                UIApplication.shared.open(AppEnvironment.privacyPolicyURL)
            } label: {
                settingsAccessoryRow(
                    title: LocalizationManager.shared.localized("settings.privacy_policy"),
                    leading: {
                        Image(systemName: "hand.raised")
                            .font(AppFont.subheadline(weight: .medium))
                    }
                )
            }
            .buttonStyle(.plain)

            Button {
                HapticFeedback.shared.triggerImpactFeedback(style: .light)
                UIApplication.shared.open(AppEnvironment.termsOfUseURL)
            } label: {
                settingsAccessoryRow(
                    title: LocalizationManager.shared.localized("settings.terms_of_use"),
                    leading: {
                        Image(systemName: "doc.text")
                            .font(AppFont.subheadline(weight: .medium))
                    }
                )
            }
            .buttonStyle(.plain)
        }
        .fullScreenCover(isPresented: $isShowingAbout) {
            AboutMMSRemoteView()
        }
    }

    // Keeps settings rows visually consistent while allowing SF Symbols or asset icons.
    private func settingsAccessoryRow<Leading: View>(
        title: String,
        @ViewBuilder leading: () -> Leading
    ) -> some View {
        HStack(spacing: 8) {
            leading()
            Text(title)
                .font(AppFont.subheadline(weight: .medium))
            Spacer()
            Image(systemName: "chevron.right")
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}

private struct SettingsTrustedComputerCard: View {
    let presentation: CodexTrustedPairPresentation
    let connectionStatusLabel: String
    let onEditName: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.06))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(localized: "settings.computer")
                            .font(AppFont.caption(weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text(presentation.name)
                            .font(AppFont.subheadline(weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 8)

                Button(action: onEditName) {
                    Image(systemName: "pencil")
                        .font(AppFont.caption(weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Color.primary.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizationManager.shared.localized("settings.edit_computer_name"))
            }

            HStack(spacing: 8) {
                SettingsStatusPill(label: connectionStatusLabel.capitalized)

                if let title = compactTitle {
                    SettingsStatusPill(label: title)
                }
            }

            if let systemName = presentation.systemName,
               !systemName.isEmpty {
                labeledRow(LocalizationManager.shared.localized("settings.computer_system"), value: systemName)
            }

            if let detail = presentation.detail,
               !detail.isEmpty {
                labeledRow(LocalizationManager.shared.localized("settings.computer_status"), value: detail)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemFill).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var compactTitle: String? {
        let trimmed = presentation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @ViewBuilder
    private func labeledRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(AppFont.caption(weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)

            Text(value)
                .font(AppFont.subheadline())
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsStatusPill: View {
    let label: String

    var body: some View {
        Text(label)
            .font(AppFont.caption(weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
    }
}

private struct SettingsComputerNameSheet: View {
    @Binding var nickname: String
    let currentName: String
    let systemName: String

    @Environment(\.dismiss) private var dismiss
    @State private var draftNickname = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                        Text(localized: "settings.computer_name")
                        .font(AppFont.subheadline(weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(currentName)
                        .font(AppFont.caption())
                        .foregroundStyle(.secondary)
                }

                TextField(systemName, text: $draftNickname)
                    .textInputAutocapitalization(.words)
                    .disableAutocorrection(true)
                    .font(AppFont.subheadline())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.secondarySystemFill))
                    )

                Text(localized: "settings.computer_name_hint")
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)

                VStack(spacing: 10) {
                    SettingsButton(LocalizationManager.shared.localized("settings.use_default"), role: .cancel) {
                        nickname = ""
                        dismiss()
                    }
                    .opacity(canResetToDefault ? 1 : 0.5)
                    .disabled(!canResetToDefault)

                    SettingsButton(LocalizationManager.shared.localized("settings.save")) {
                        nickname = draftNickname
                        dismiss()
                    }
                    .opacity(canSave ? 1 : 0.5)
                    .disabled(!canSave)
                }

                Spacer(minLength: 0)
            }
            .padding(20)
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
            .navigationTitle(Text(localized: "settings.edit_computer_name"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizationManager.shared.localized("settings.close")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                draftNickname = nickname
            }
        }
    }

    private var canSave: Bool {
        draftNickname != nickname
    }

    private var canResetToDefault: Bool {
        !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(CodexService())
    }
}
