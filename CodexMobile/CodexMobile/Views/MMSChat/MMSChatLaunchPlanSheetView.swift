// FILE: MMSChatLaunchPlanSheetView.swift
// Purpose: Presents read-only MMS model metadata and dry-run launch-plan preview.
// Layer: View
// Exports: MMSChatLaunchPlanSheetView
// Depends on: SwiftUI, CodexService, MMSMetadataModels

import SwiftUI

struct MMSChatLaunchPlanSheetView: View {
    @Environment(CodexService.self) private var codex
    @Environment(\.dismiss) private var dismiss

    let defaultCwd: String

    @State private var cwd: String
    @State private var providers: [MMSProviderSummary] = []
    @State private var presets: [MMSPresetSummary] = []
    @State private var models: [MMSModelSummary] = []
    @State private var selectedProviderId = ""
    @State private var selectedModelId = ""
    @State private var selectedPresetId = ""
    @State private var configSource = "unknown"
    @State private var configFound = false
    @State private var launchPlan: MMSLaunchPlanResponse?
    @State private var isLoadingMetadata = false
    @State private var isLoadingPlan = false
    @State private var errorMessage: String?
    @State private var compatibilityMessage: String?

    init(defaultCwd: String) {
        self.defaultCwd = defaultCwd
        self._cwd = State(initialValue: defaultCwd)
    }

    var body: some View {
        NavigationStack {
            List {
                statusSection
                cwdSection
                presetSection
                providerSection
                planSection
            }
            .navigationTitle(LocalizationManager.shared.localized("mmschat.model_picker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizationManager.shared.localized("common.close")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(LocalizationManager.shared.localized("mmschat.model_picker.preview")) {
                        Task { await loadLaunchPlan() }
                    }
                    .disabled(!canPreview)
                }
            }
            .task {
                await loadMetadata()
            }
            .alert(
                LocalizationManager.shared.localized("mmschat.error_title"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(LocalizationManager.shared.localized("common.ok"), role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var statusSection: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: configFound ? "checkmark.seal" : "exclamationmark.triangle")
                    .foregroundStyle(configFound ? .green : .orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text(configFound ? LocalizationManager.shared.localized("mmschat.model_picker.config_found") : LocalizationManager.shared.localized("mmschat.model_picker.config_missing"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(String(format: LocalizationManager.shared.localized("mmschat.model_picker.source_format"), configSource))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            if isLoadingMetadata {
                ProgressView(LocalizationManager.shared.localized("mmschat.model_picker.loading"))
            }
            if !configFound && !isLoadingMetadata {
                Text(LocalizationManager.shared.localized("mmschat.model_picker.no_config_description"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if let compatibilityMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(compatibilityMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        } footer: {
            Text(LocalizationManager.shared.localized("mmschat.model_picker.dry_run_notice"))
        }
    }

    private var cwdSection: some View {
        Section {
            TextField(LocalizationManager.shared.localized("mmschat.model_picker.cwd_placeholder"), text: $cwd)
                .autocorrectionDisabled()
        } header: {
            Text(LocalizationManager.shared.localized("mmschat.model_picker.cwd"))
        }
    }

    private var presetSection: some View {
        Section {
            Picker(LocalizationManager.shared.localized("mmschat.model_picker.preset"), selection: $selectedPresetId) {
                Text(LocalizationManager.shared.localized("mmschat.model_picker.no_preset")).tag("")
                ForEach(presets) { preset in
                    Text(presetTitle(preset)).tag(preset.id)
                }
            }
            .disabled(presets.isEmpty)

            if presets.isEmpty && !isLoadingMetadata {
                Text(LocalizationManager.shared.localized("mmschat.model_picker.no_presets"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(LocalizationManager.shared.localized("mmschat.model_picker.preset"))
        }
    }

    private var providerSection: some View {
        Section {
            Picker(LocalizationManager.shared.localized("mmschat.model_picker.provider"), selection: $selectedProviderId) {
                ForEach(providers) { provider in
                    Text(providerTitle(provider)).tag(provider.id)
                }
            }
            .disabled(!selectedPresetId.isEmpty || providers.isEmpty)
            .onChange(of: selectedProviderId) { _, _ in
                selectDefaultModelForProvider()
            }

            Picker(LocalizationManager.shared.localized("mmschat.model_picker.model"), selection: $selectedModelId) {
                ForEach(modelsForSelectedProvider) { model in
                    Text(modelTitle(model)).tag(model.id)
                }
            }
            .disabled(!selectedPresetId.isEmpty || modelsForSelectedProvider.isEmpty)

            if providers.isEmpty && !isLoadingMetadata {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizationManager.shared.localized("mmschat.model_picker.no_providers_title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(LocalizationManager.shared.localized("mmschat.model_picker.no_providers_description"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(LocalizationManager.shared.localized("mmschat.model_picker.provider_model"))
        } footer: {
            if !selectedPresetId.isEmpty {
                Text(LocalizationManager.shared.localized("mmschat.model_picker.preset_overrides"))
            } else if !canPreview {
                Text(LocalizationManager.shared.localized("mmschat.model_picker.preview_disabled_reason"))
            }
        }
    }

    private var planSection: some View {
        Section {
            if isLoadingPlan {
                ProgressView(LocalizationManager.shared.localized("mmschat.model_picker.preview_loading"))
            } else if let launchPlan {
                LabeledContent(LocalizationManager.shared.localized("mmschat.model_picker.command"), value: launchPlan.command)
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizationManager.shared.localized("mmschat.model_picker.argv"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(launchPlan.argv.joined(separator: " "))
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                }
                LabeledContent(LocalizationManager.shared.localized("mmschat.model_picker.cwd"), value: launchPlan.cwd)
                if let fingerprint = launchPlan.profile.launchProfileFingerprint {
                    LabeledContent(LocalizationManager.shared.localized("mmschat.model_picker.fingerprint"), value: fingerprint)
                }
                LabeledContent(
                    LocalizationManager.shared.localized("mmschat.model_picker.credential_flag"),
                    value: launchPlan.profile.credentialPresent ? LocalizationManager.shared.localized("common.yes") : LocalizationManager.shared.localized("common.no")
                )
                Button(LocalizationManager.shared.localized("mmschat.model_picker.launch_disabled")) {}
                    .disabled(true)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizationManager.shared.localized("mmschat.model_picker.preview_empty"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if !configFound {
                        Text(LocalizationManager.shared.localized("mmschat.model_picker.no_config_description"))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    } else if providers.isEmpty {
                        Text(LocalizationManager.shared.localized("mmschat.model_picker.no_providers_description"))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        } header: {
            Text(LocalizationManager.shared.localized("mmschat.model_picker.plan_preview"))
        }
    }

    private var modelsForSelectedProvider: [MMSModelSummary] {
        models.filter { $0.provider == selectedProviderId }
    }

    private var selectedModel: MMSModelSummary? {
        models.first { $0.id == selectedModelId }
    }

    private var canPreview: Bool {
        guard codex.isConnected, !isLoadingMetadata, !isLoadingPlan, !cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        if !selectedPresetId.isEmpty { return true }
        return selectedModel != nil
    }

    private func loadMetadata() async {
        guard codex.isConnected else {
            errorMessage = LocalizationManager.shared.localized("mmschat.error_disconnected")
            return
        }
        isLoadingMetadata = true
        errorMessage = nil
        compatibilityMessage = nil
        do {
            let providerResponse = try await codex.mmsProviders()
            let presetResponse = try await codex.mmsPresets()
            let modelResponse = try await codex.mmsModels()
            providers = providerResponse.providers
            presets = presetResponse.presets
            models = modelResponse.models
            configSource = providerResponse.source
            configFound = providerResponse.found
            selectDefaults()
        } catch {
            if MMSChatErrorClassifier.classify(error) == .bridgeMismatch {
                configSource = "bridge"
                configFound = false
                providers = []
                presets = []
                models = []
                launchPlan = nil
                compatibilityMessage = LocalizationManager.shared.localized("mmschat.error_bridge_mismatch")
            } else {
                errorMessage = MMSChatErrorClassifier.localizedMessage(for: error)
            }
        }
        isLoadingMetadata = false
    }

    private func loadLaunchPlan() async {
        guard canPreview else { return }
        isLoadingPlan = true
        errorMessage = nil
        compatibilityMessage = nil
        do {
            let trimmedCwd = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
            if !selectedPresetId.isEmpty {
                launchPlan = try await codex.mmsLaunchPlan(cwd: trimmedCwd, preset: selectedPresetId)
            } else if let selectedModel {
                launchPlan = try await codex.mmsLaunchPlan(cwd: trimmedCwd, provider: selectedModel.provider, model: selectedModel.model)
            }
        } catch {
            if MMSChatErrorClassifier.classify(error) == .bridgeMismatch {
                launchPlan = nil
                compatibilityMessage = LocalizationManager.shared.localized("mmschat.error_bridge_mismatch")
            } else {
                errorMessage = MMSChatErrorClassifier.localizedMessage(for: error)
            }
        }
        isLoadingPlan = false
    }

    private func selectDefaults() {
        if selectedProviderId.isEmpty {
            selectedProviderId = providers.first?.id ?? ""
        }
        selectDefaultModelForProvider()
    }

    private func selectDefaultModelForProvider() {
        let providerModels = modelsForSelectedProvider
        selectedModelId = providerModels.first(where: { $0.isDefault })?.id ?? providerModels.first?.id ?? ""
    }

    private func providerTitle(_ provider: MMSProviderSummary) -> String {
        provider.credentialPresent ? "\(provider.name) *" : provider.name
    }

    private func modelTitle(_ model: MMSModelSummary) -> String {
        model.isDefault ? "\(model.model) (\(LocalizationManager.shared.localized("mmschat.model_picker.default_badge")))" : model.model
    }

    private func presetTitle(_ preset: MMSPresetSummary) -> String {
        let model = preset.model ?? preset.defaultModel ?? "-"
        return "\(preset.id) - \(preset.provider ?? "-") / \(model)"
    }
}
