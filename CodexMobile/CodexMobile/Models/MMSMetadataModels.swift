// FILE: MMSMetadataModels.swift
// Purpose: Models read-only MMS provider metadata and dry-run launch plan responses.
// Layer: Model
// Exports: MMS metadata response and launch-plan models
// Depends on: Foundation

import Foundation

struct MMSProviderSummary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let name: String
    let defaultModel: String?
    let models: [String]
    let visible: Bool
    let credentialPresent: Bool
}

struct MMSProvidersResponse: Codable, Hashable, Sendable {
    let providers: [MMSProviderSummary]
    let source: String
    let found: Bool
}

struct MMSPresetSummary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let provider: String?
    let model: String?
    let defaultModel: String?
    let visible: Bool
    let credentialPresent: Bool
}

struct MMSPresetsResponse: Codable, Hashable, Sendable {
    let presets: [MMSPresetSummary]
    let source: String
    let found: Bool
}

struct MMSModelSummary: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let provider: String
    let providerName: String
    let model: String
    let defaultModel: String?
    let isDefault: Bool
    let credentialPresent: Bool
}

struct MMSModelsResponse: Codable, Hashable, Sendable {
    let models: [MMSModelSummary]
    let source: String
    let found: Bool
}

struct MMSLaunchProfileSummary: Codable, Hashable, Sendable {
    let agent: String?
    let provider: String?
    let model: String?
    let preset: String?
    let launchProfileName: String?
    let launchProfileFingerprint: String?
    let credentialPresent: Bool
}

struct MMSLaunchPlanConfigSummary: Codable, Hashable, Sendable {
    let found: Bool
    let source: String
}

struct MMSLaunchPlanResponse: Codable, Hashable, Sendable {
    let dryRun: Bool
    let command: String
    let argv: [String]
    let cwd: String
    let spawn: Bool
    let profile: MMSLaunchProfileSummary
    let config: MMSLaunchPlanConfigSummary
}
