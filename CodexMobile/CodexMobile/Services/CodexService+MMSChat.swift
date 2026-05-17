// FILE: CodexService+MMSChat.swift
// Purpose: Bridge RPC helpers for MMSChat session list/detail/hide/cache-clear/open-visible.
// Layer: Service
// Exports: CodexService MMSChat operations
// Depends on: Foundation, MMSChatModels, JSONValue, RPCMessage, CodexTimestampParser

import Foundation

// MARK: - JSONValue Decoding Helpers for MMSChatModels

extension MMSChatSession {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatSession")
        }
        self.mmschatId = obj["mmschatId"]?.stringValue ?? ""
        self.nativeClaudeSessionId = obj["nativeClaudeSessionId"]?.stringValue
        self.nativeClaudeSessionStatus = obj["nativeClaudeSessionStatus"].flatMap { MMSChatNativeSessionStatus(rawValue: $0.stringValue ?? "") }
        self.title = obj["title"]?.stringValue
        self.cwd = obj["cwd"]?.stringValue ?? ""
        self.project = obj["project"]?.stringValue
        self.agent = obj["agent"]?.stringValue ?? "claude"
        self.provider = obj["provider"]?.stringValue
        self.model = obj["model"]?.stringValue
        self.launchProfileName = obj["launchProfileName"]?.stringValue
        self.launchProfileFingerprint = obj["launchProfileFingerprint"]?.stringValue
        self.authSecretRef = obj["authSecretRef"]?.stringValue
        self.tmuxPaneId = obj["tmuxPaneId"]?.stringValue
        self.tmuxSessionName = obj["tmuxSessionName"]?.stringValue
        self.pid = obj["pid"]?.intValue
        self.status = obj["status"].flatMap { MMSChatStatus(rawValue: $0.stringValue ?? "") } ?? .unknown
        self.createdAt = CodexTimestampParser.parseString(obj["createdAt"]?.stringValue) ?? Date.distantPast
        self.lastActivityAt = CodexTimestampParser.parseString(obj["lastActivityAt"]?.stringValue) ?? Date.distantPast
        self.lastPreviewText = obj["lastPreviewText"]?.stringValue
        self.hidden = obj["hidden"]?.boolValue ?? false
        self.transcriptCacheState = obj["transcriptCacheState"].flatMap { MMSChatTranscriptCacheState(rawValue: $0.stringValue ?? "") }
        if let meta = obj["metadata"]?.objectValue {
            self.metadata = Dictionary(uniqueKeysWithValues: meta.compactMap { k, v in
                v.stringValue.map { (k, $0) }
            })
        } else {
            self.metadata = nil
        }
    }
}

extension MMSChatListResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatListResponse")
        }
        let rawSessions = obj["sessions"]?.arrayValue ?? []
        self.sessions = try rawSessions.map { try MMSChatSession(json: $0) }
        self.source = obj["source"]?.stringValue ?? "registry"
        self.sortedBy = obj["sortedBy"]?.stringValue ?? "lastActivityAt"
    }
}

extension MMSChatDetailResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatDetailResponse")
        }
        self.session = try MMSChatSession(json: obj["session"] ?? .null)
        if let transcriptJSON = obj["transcript"] {
            self.transcript = try MMSChatTranscriptSnapshot(json: transcriptJSON)
        } else {
            self.transcript = nil
        }
        if let liveActionsJSON = obj["liveActions"] {
            self.liveActions = try MMSChatLiveActionsState(json: liveActionsJSON)
        } else {
            self.liveActions = nil
        }
    }
}

extension MMSChatLiveActionsState {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatLiveActionsState")
        }
        self.enabled = obj["enabled"]?.boolValue ?? false
        self.envName = obj["envName"]?.stringValue
        self.requiresConfirmation = obj["requiresConfirmation"]?.boolValue
        self.guardText = obj["guard"]?.stringValue
        self.supportedMethods = obj["supportedMethods"]?.arrayValue?.compactMap(\.stringValue)
    }
}

extension MMSChatTranscriptSnapshot {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatTranscriptSnapshot")
        }
        self.source = obj["source"].flatMap { MMSChatTranscriptSource(rawValue: $0.stringValue ?? "") } ?? .unavailable
        self.nativePathState = obj["nativePathState"].flatMap { MMSChatNativePathState(rawValue: $0.stringValue ?? "") } ?? .pending
        let rawMessages = obj["messages"]?.arrayValue ?? []
        self.messages = try rawMessages.map { try MMSChatTranscriptMessage(json: $0) }
        self.rawPreviewText = obj["rawPreviewText"]?.stringValue
    }
}

extension MMSChatTranscriptMessage {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatTranscriptMessage")
        }
        self.id = obj["id"]?.stringValue ?? UUID().uuidString
        self.role = obj["role"]?.stringValue ?? "unknown"
        self.createdAt = CodexTimestampParser.parseString(obj["createdAt"]?.stringValue)
        let rawContent = obj["content"]?.arrayValue ?? []
        self.content = rawContent.compactMap { item -> MMSChatTranscriptContent? in
            guard let itemObj = item.objectValue else { return nil }
            return MMSChatTranscriptContent(
                type: itemObj["type"]?.stringValue ?? "text",
                text: itemObj["text"]?.stringValue
            )
        }
    }
}

extension MMSChatSendResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatSendResponse")
        }
        self.accepted = obj["accepted"]?.boolValue ?? false
        self.disabled = obj["disabled"]?.boolValue
        self.errorCode = obj["errorCode"].flatMap { MMSChatErrorCode(rawValue: $0.stringValue ?? "") }
    }
}

extension MMSChatHideResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatHideResponse")
        }
        self.session = try MMSChatSession(json: obj["session"] ?? .null)
    }
}

extension MMSChatClearCacheResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatClearCacheResponse")
        }
        self.session = try MMSChatSession(json: obj["session"] ?? .null)
        self.cacheCleared = obj["cacheCleared"]?.boolValue ?? false
    }
}

extension MMSChatDemoSeedResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatDemoSeedResponse")
        }
        self.demo = obj["demo"]?.boolValue ?? false
        self.seeded = obj["seeded"]?.boolValue ?? false
        self.source = obj["source"]?.stringValue ?? "unknown"
        let rawSessions = obj["sessions"]?.arrayValue ?? []
        self.sessions = try rawSessions.map { try MMSChatSession(json: $0) }
    }
}

extension MMSChatOpenVisibleResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatOpenVisibleResponse")
        }
        self.opened = obj["opened"]?.boolValue ?? false
        self.visibleApp = obj["visibleApp"]?.stringValue
    }
}

extension MMSChatResumeResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatResumeResponse")
        }
        self.session = try MMSChatSession(json: obj["session"] ?? .null)
        self.resumeStarted = obj["resumeStarted"]?.boolValue ?? false
    }
}

// MARK: - MMS Metadata JSONValue Decoding Helpers

extension MMSProviderSummary {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSProviderSummary")
        }
        self.id = obj["id"]?.stringValue ?? ""
        self.name = obj["name"]?.stringValue ?? id
        self.defaultModel = obj["defaultModel"]?.stringValue
        self.models = obj["models"]?.arrayValue?.compactMap(\.stringValue) ?? []
        self.visible = obj["visible"]?.boolValue ?? true
        self.credentialPresent = obj["credentialPresent"]?.boolValue ?? false
    }
}

extension MMSProvidersResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSProvidersResponse")
        }
        self.providers = try (obj["providers"]?.arrayValue ?? []).map { try MMSProviderSummary(json: $0) }
        self.source = obj["source"]?.stringValue ?? "unknown"
        self.found = obj["found"]?.boolValue ?? false
    }
}

extension MMSPresetSummary {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSPresetSummary")
        }
        self.id = obj["id"]?.stringValue ?? ""
        self.provider = obj["provider"]?.stringValue
        self.model = obj["model"]?.stringValue
        self.defaultModel = obj["defaultModel"]?.stringValue
        self.visible = obj["visible"]?.boolValue ?? true
        self.credentialPresent = obj["credentialPresent"]?.boolValue ?? false
    }
}

extension MMSPresetsResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSPresetsResponse")
        }
        self.presets = try (obj["presets"]?.arrayValue ?? []).map { try MMSPresetSummary(json: $0) }
        self.source = obj["source"]?.stringValue ?? "unknown"
        self.found = obj["found"]?.boolValue ?? false
    }
}

extension MMSModelSummary {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSModelSummary")
        }
        self.id = obj["id"]?.stringValue ?? ""
        self.provider = obj["provider"]?.stringValue ?? ""
        self.providerName = obj["providerName"]?.stringValue ?? provider
        self.model = obj["model"]?.stringValue ?? ""
        self.defaultModel = obj["defaultModel"]?.stringValue
        self.isDefault = obj["isDefault"]?.boolValue ?? false
        self.credentialPresent = obj["credentialPresent"]?.boolValue ?? false
    }
}

extension MMSModelsResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSModelsResponse")
        }
        self.models = try (obj["models"]?.arrayValue ?? []).map { try MMSModelSummary(json: $0) }
        self.source = obj["source"]?.stringValue ?? "unknown"
        self.found = obj["found"]?.boolValue ?? false
    }
}

extension MMSLaunchProfileSummary {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSLaunchProfileSummary")
        }
        self.agent = obj["agent"]?.stringValue
        self.provider = obj["provider"]?.stringValue
        self.model = obj["model"]?.stringValue
        self.preset = obj["preset"]?.stringValue
        self.launchProfileName = obj["launchProfileName"]?.stringValue
        self.launchProfileFingerprint = obj["launchProfileFingerprint"]?.stringValue
        self.credentialPresent = obj["credentialPresent"]?.boolValue ?? false
    }
}

extension MMSLaunchPlanConfigSummary {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSLaunchPlanConfigSummary")
        }
        self.found = obj["found"]?.boolValue ?? false
        self.source = obj["source"]?.stringValue ?? "unknown"
    }
}

extension MMSLaunchPlanResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSLaunchPlanResponse")
        }
        self.dryRun = obj["dryRun"]?.boolValue ?? true
        self.command = obj["command"]?.stringValue ?? "mms"
        self.argv = obj["argv"]?.arrayValue?.compactMap(\.stringValue) ?? []
        self.cwd = obj["cwd"]?.stringValue ?? ""
        self.spawn = obj["spawn"]?.boolValue ?? false
        self.profile = try MMSLaunchProfileSummary(json: obj["profile"] ?? .object([:]))
        self.config = try MMSLaunchPlanConfigSummary(json: obj["config"] ?? .object([:]))
    }
}

// MARK: - Decode Error

enum MMSChatDecodeError: Error, LocalizedError {
    case invalidShape(String)

    var errorDescription: String? {
        switch self {
        case .invalidShape(let type):
            return "MMSChat decode error: invalid shape for \(type)"
        }
    }
}

// MARK: - Service Extension

extension CodexService {

    @discardableResult
    func mmschatList(
        includeHidden: Bool = false,
        status: [MMSChatStatus]? = nil,
        cwd: String? = nil,
        limit: Int? = nil
    ) async throws -> MMSChatListResponse {
        var params: RPCObject = ["includeHidden": .bool(includeHidden)]
        if let status, !status.isEmpty {
            params["status"] = .array(status.map { .string($0.rawValue) })
        }
        if let cwd { params["cwd"] = .string(cwd) }
        if let limit { params["limit"] = .integer(limit) }

        let response = try await sendRequest(
            method: "mmschat/list",
            params: .object(params),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "MMSChat list timed out while contacting the Mac bridge."
        )
        return try MMSChatListResponse(json: response.result ?? .null)
    }

    func mmschatDetail(
        mmschatId: String,
        includeTranscript: Bool = true,
        transcriptMode: MMSChatTranscriptSource = .nativeJSONL
    ) async throws -> MMSChatDetailResponse {
        var params: RPCObject = ["mmschatId": .string(mmschatId)]
        params["includeTranscript"] = .bool(includeTranscript)
        params["transcriptMode"] = .string(transcriptMode.rawValue)

        let response = try await sendRequest(
            method: "mmschat/detail",
            params: .object(params),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "MMSChat detail timed out while contacting the Mac bridge."
        )
        return try MMSChatDetailResponse(json: response.result ?? .null)
    }

    func mmschatHide(mmschatId: String, hidden: Bool = true) async throws -> MMSChatHideResponse {
        let params: RPCObject = [
            "mmschatId": .string(mmschatId),
            "hidden": .bool(hidden),
        ]
        let response = try await sendRequest(
            method: "mmschat/hide",
            params: .object(params),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "MMSChat hide timed out."
        )
        return try MMSChatHideResponse(json: response.result ?? .null)
    }

    func mmschatCacheClear(mmschatId: String) async throws -> MMSChatClearCacheResponse {
        let params: RPCObject = ["mmschatId": .string(mmschatId)]
        let response = try await sendRequest(
            method: "mmschat/cache/clear",
            params: .object(params),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "MMSChat cache clear timed out."
        )
        return try MMSChatClearCacheResponse(json: response.result ?? .null)
    }

    func mmschatDemoSeed() async throws -> MMSChatDemoSeedResponse {
        let response = try await sendRequest(
            method: MMSChatMethod.demoSeed.rawValue,
            params: .object([:]),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "MMSChat demo seed timed out while contacting the Mac bridge."
        )
        return try MMSChatDemoSeedResponse(json: response.result ?? .null)
    }

    func mmschatOpenVisible(mmschatId: String, visibleApp: String? = nil) async throws -> MMSChatOpenVisibleResponse {
        var params: RPCObject = ["mmschatId": .string(mmschatId)]
        params["confirmLiveAction"] = .bool(true)
        if let visibleApp { params["visibleApp"] = .string(visibleApp) }

        let response = try await sendRequest(
            method: "mmschat/openVisible",
            params: .object(params),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "MMSChat open visible timed out."
        )
        return try MMSChatOpenVisibleResponse(json: response.result ?? .null)
    }

    func mmschatResume(mmschatId: String) async throws -> MMSChatResumeResponse {
        let params: RPCObject = [
            "mmschatId": .string(mmschatId),
            "confirmLiveAction": .bool(true),
        ]
        let response = try await sendRequest(
            method: "mmschat/resume",
            params: .object(params),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "MMSChat resume timed out."
        )
        return try MMSChatResumeResponse(json: response.result ?? .null)
    }

    func mmschatSend(mmschatId: String, text: String) async throws -> MMSChatSendResponse {
        let params: RPCObject = [
            "mmschatId": .string(mmschatId),
            "text": .string(text),
            "confirmLiveAction": .bool(true),
        ]
        let response = try await sendRequest(
            method: "mmschat/send",
            params: .object(params),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "MMSChat send timed out."
        )
        return try MMSChatSendResponse(json: response.result ?? .null)
    }

    func mmsProviders() async throws -> MMSProvidersResponse {
        let response = try await sendRequest(
            method: "mms/providers",
            params: .object([:]),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "MMS provider metadata timed out while contacting the Mac bridge."
        )
        return try MMSProvidersResponse(json: response.result ?? .null)
    }

    func mmsPresets() async throws -> MMSPresetsResponse {
        let response = try await sendRequest(
            method: "mms/presets",
            params: .object([:]),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "MMS preset metadata timed out while contacting the Mac bridge."
        )
        return try MMSPresetsResponse(json: response.result ?? .null)
    }

    func mmsModels() async throws -> MMSModelsResponse {
        let response = try await sendRequest(
            method: "mms/models",
            params: .object([:]),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "MMS model metadata timed out while contacting the Mac bridge."
        )
        return try MMSModelsResponse(json: response.result ?? .null)
    }

    func mmsLaunchPlan(cwd: String, preset: String? = nil, provider: String? = nil, model: String? = nil) async throws -> MMSLaunchPlanResponse {
        var params: RPCObject = ["cwd": .string(cwd)]
        if let preset { params["preset"] = .string(preset) }
        if let provider { params["provider"] = .string(provider) }
        if let model { params["model"] = .string(model) }

        let response = try await sendRequest(
            method: "mms/launch/plan",
            params: .object(params),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "MMS launch plan timed out while contacting the Mac bridge."
        )
        return try MMSLaunchPlanResponse(json: response.result ?? .null)
    }
}
