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

extension MMSChatOpenVisibleResponse {
    init(json: JSONValue) throws {
        guard let obj = json.objectValue else {
            throw MMSChatDecodeError.invalidShape("MMSChatOpenVisibleResponse")
        }
        self.opened = obj["opened"]?.boolValue ?? false
        self.visibleApp = obj["visibleApp"]?.stringValue
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

    func mmschatOpenVisible(mmschatId: String, visibleApp: String? = nil) async throws -> MMSChatOpenVisibleResponse {
        var params: RPCObject = ["mmschatId": .string(mmschatId)]
        if let visibleApp { params["visibleApp"] = .string(visibleApp) }

        let response = try await sendRequest(
            method: "mmschat/openVisible",
            params: .object(params),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "MMSChat open visible timed out."
        )
        return try MMSChatOpenVisibleResponse(json: response.result ?? .null)
    }

    // Send is feature-flagged off for P4. Always returns send_disabled until P5/P6.
    func mmschatSend(mmschatId: String, text: String) async throws -> MMSChatSendResponse {
        let params: RPCObject = [
            "mmschatId": .string(mmschatId),
            "text": .string(text),
            "featureFlag": .bool(false),
        ]
        let response = try await sendRequest(
            method: "mmschat/send",
            params: .object(params),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "MMSChat send timed out."
        )
        return try MMSChatSendResponse(json: response.result ?? .null)
    }
}
