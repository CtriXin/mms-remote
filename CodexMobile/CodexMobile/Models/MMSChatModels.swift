// FILE: MMSChatModels.swift
// Purpose: Models MMSChat protocol sessions, requests, responses, and errors.
// Layer: Model
// Exports: MMSChatSession, MMSChatStatus, MMSChat RPC request/response models
// Depends on: Foundation

import Foundation

enum MMSChatStatus: String, Codable, Hashable, Sendable {
    case pending
    case running
    case idle
    case dead
    case needsResume = "needs-resume"
    case unknown
}

enum MMSChatNativeSessionStatus: String, Codable, Hashable, Sendable {
    case pending
    case confirmed
    case unavailable
}

enum MMSChatTranscriptCacheState: String, Codable, Hashable, Sendable {
    case empty
    case stale
    case fresh
    case rawFallback = "raw-fallback"
}

enum MMSChatTranscriptSource: String, Codable, Hashable, Sendable {
    case nativeJSONL = "native-jsonl"
    case rawTmuxPreview = "raw-tmux-preview"
    case unavailable
}

enum MMSChatNativePathState: String, Codable, Hashable, Sendable {
    case pending
    case confirmed
    case missing
    case unreadable
}

enum MMSChatErrorCode: String, Codable, Hashable, Sendable {
    case invalidParams = "invalid_params"
    case sessionNotFound = "session_not_found"
    case nativeSessionPending = "native_session_pending"
    case paneDead = "pane_dead"
    case busy
    case sendDisabled = "send_disabled"
    case resumeFailed = "resume_failed"
    case unsupportedMethod = "unsupported_method"
    case secretRejected = "secret_rejected"
}

enum MMSChatMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case list = "mmschat/list"
    case detail = "mmschat/detail"
    case attach = "mmschat/attach"
    case send = "mmschat/send"
    case resume = "mmschat/resume"
    case openVisible = "mmschat/openVisible"
    case kill = "mmschat/kill"
    case hide = "mmschat/hide"
    case clearCache = "mmschat/cache/clear"
    case demoSeed = "mmschat/demo/seed"
}

struct MMSChatSession: Identifiable, Codable, Hashable, Sendable {
    var id: String { mmschatId }

    let mmschatId: String
    let nativeClaudeSessionId: String?
    let nativeClaudeSessionStatus: MMSChatNativeSessionStatus?
    let title: String?
    let cwd: String
    let project: String?
    let agent: String
    let provider: String?
    let model: String?
    let launchProfileName: String?
    let launchProfileFingerprint: String?
    let authSecretRef: String?
    let tmuxPaneId: String?
    let tmuxSessionName: String?
    let pid: Int?
    let status: MMSChatStatus
    let createdAt: Date
    let lastActivityAt: Date
    let lastPreviewText: String?
    let hidden: Bool
    let transcriptCacheState: MMSChatTranscriptCacheState?
    let metadata: [String: String]?
}

struct MMSChatListParams: Codable, Hashable, Sendable {
    let includeHidden: Bool?
    let status: [MMSChatStatus]?
    let cwd: String?
    let limit: Int?
}

struct MMSChatListResponse: Codable, Hashable, Sendable {
    let sessions: [MMSChatSession]
    let source: String
    let sortedBy: String
}

struct MMSChatDetailParams: Codable, Hashable, Sendable {
    let mmschatId: String
    let includeTranscript: Bool?
    let transcriptMode: MMSChatTranscriptSource?
}

struct MMSChatTranscriptMessage: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let role: String
    let createdAt: Date?
    let content: [MMSChatTranscriptContent]
}

struct MMSChatTranscriptContent: Codable, Hashable, Sendable {
    let type: String
    let text: String?
}

struct MMSChatTranscriptSnapshot: Codable, Hashable, Sendable {
    let source: MMSChatTranscriptSource
    let nativePathState: MMSChatNativePathState
    let messages: [MMSChatTranscriptMessage]
    let rawPreviewText: String?
}

struct MMSChatDetailResponse: Codable, Hashable, Sendable {
    let session: MMSChatSession
    let transcript: MMSChatTranscriptSnapshot?
}

struct MMSChatAttachParams: Codable, Hashable, Sendable {
    let tmuxPaneId: String?
    let tmuxSessionName: String?
    let cwd: String
    let nativeClaudeSessionId: String?
    let provider: String?
    let model: String?
    let launchProfileName: String?
    let launchProfileFingerprint: String?
    let authSecretRef: String?
}

struct MMSChatAttachResponse: Codable, Hashable, Sendable {
    let session: MMSChatSession
    let attached: Bool
}

struct MMSChatSendParams: Codable, Hashable, Sendable {
    let mmschatId: String
    let text: String
    let clientMessageId: String?
    let featureFlag: Bool?
}

struct MMSChatSendResponse: Codable, Hashable, Sendable {
    let accepted: Bool
    let disabled: Bool?
    let errorCode: MMSChatErrorCode?
}

struct MMSChatResumeParams: Codable, Hashable, Sendable {
    let mmschatId: String
    let launchProfileFingerprint: String?
}

struct MMSChatResumeResponse: Codable, Hashable, Sendable {
    let session: MMSChatSession
    let resumeStarted: Bool
}

struct MMSChatOpenVisibleParams: Codable, Hashable, Sendable {
    let mmschatId: String
    let visibleApp: String?
}

struct MMSChatOpenVisibleResponse: Codable, Hashable, Sendable {
    let opened: Bool
    let visibleApp: String?
}

struct MMSChatKillParams: Codable, Hashable, Sendable {
    let mmschatId: String
}

struct MMSChatKillResponse: Codable, Hashable, Sendable {
    let session: MMSChatSession
    let killed: Bool
}

struct MMSChatHideParams: Codable, Hashable, Sendable {
    let mmschatId: String
    let hidden: Bool?
}

struct MMSChatHideResponse: Codable, Hashable, Sendable {
    let session: MMSChatSession
}

struct MMSChatClearCacheParams: Codable, Hashable, Sendable {
    let mmschatId: String
}

struct MMSChatClearCacheResponse: Codable, Hashable, Sendable {
    let session: MMSChatSession
    let cacheCleared: Bool
}

struct MMSChatDemoSeedResponse: Codable, Hashable, Sendable {
    let demo: Bool
    let seeded: Bool
    let source: String
    let sessions: [MMSChatSession]
}

extension MMSChatStatus {
    var resumable: Bool {
        self == .dead || self == .needsResume || self == .unknown
    }
}
