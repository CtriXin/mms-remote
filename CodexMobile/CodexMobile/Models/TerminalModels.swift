// FILE: TerminalModels.swift
// Purpose: Models managed tmux terminal sessions/windows/panes and snapshots.
// Layer: Model
// Exports: ManagedTerminalSession, ManagedTerminalWindow, ManagedTerminalPane, ManagedTerminalSnapshot, ManagedTerminalList
// Depends on: Foundation, JSONValue

import Foundation

struct ManagedTerminalSession: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let windowCount: Int
    let attachedCount: Int
    let createdAt: Int
}

struct ManagedTerminalWindow: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let sessionId: String
    let sessionName: String
    let index: Int
    let name: String
    let active: Bool
    let paneCount: Int
    let layout: String
    let windowKey: String
}

struct ManagedTerminalPane: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let paneId: String
    let paneKey: String
    let target: String
    let sessionId: String
    let sessionName: String
    let windowId: String
    let windowIndex: Int
    let windowName: String
    let paneIndex: Int
    let title: String
    let currentCommand: String
    let cwd: String
    let cols: Int
    let rows: Int
    let active: Bool
    let dead: Bool

    var requestTarget: String {
        firstNonEmpty(paneId, target, normalizedPaneKey, synthesizedPaneAddress, id) ?? ""
    }

    var paneAddress: String {
        normalizedPaneKey ?? synthesizedPaneAddress ?? firstNonEmpty(paneId, target, id) ?? "unknown"
    }

    var displayTitle: String {
        firstNonEmpty(title, currentCommand, sessionName, windowName, paneAddress) ?? "Terminal"
    }

    var paneDebugSummary: String {
        [
            "target=\(debugValue(requestTarget))",
            "id=\(debugValue(id))",
            "paneId=\(debugValue(paneId))",
            "paneKey=\(debugValue(paneKey))",
            "session=\(debugValue(sessionName))",
            "addr=\(debugValue(paneAddress))",
        ].joined(separator: " ")
    }

    private var normalizedPaneKey: String? {
        let key = paneKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.contains(":"), key.contains("."), !key.hasPrefix(":") else {
            return nil
        }
        return key
    }

    private var synthesizedPaneAddress: String? {
        let session = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !session.isEmpty else { return nil }
        return "\(session):\(windowIndex).\(paneIndex)"
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private func debugValue(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? "-" : normalized
    }
}

struct ManagedTerminalSnapshot: Codable, Equatable, Sendable {
    let pane: ManagedTerminalPane
    let content: String
    let capturedAt: String
}

struct ManagedTerminalList: Codable, Equatable, Sendable {
    let tmuxVersion: String
    let sessions: [ManagedTerminalSession]
    let windows: [ManagedTerminalWindow]
    let panes: [ManagedTerminalPane]
    let createdPane: ManagedTerminalPane?

    static let empty = ManagedTerminalList(
        tmuxVersion: "",
        sessions: [],
        windows: [],
        panes: [],
        createdPane: nil
    )
}

enum ManagedTerminalKey: String, CaseIterable, Identifiable, Sendable {
    case enter
    case backspace
    case tab
    case escape
    case up
    case down
    case left
    case right
    case ctrlC = "ctrl-c"
    case ctrlD = "ctrl-d"
    case ctrlZ = "ctrl-z"
    case ctrlA = "ctrl-a"
    case ctrlE = "ctrl-e"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .enter: return "Enter"
        case .backspace: return "⌫"
        case .tab: return "Tab"
        case .escape: return "Esc"
        case .up: return "↑"
        case .down: return "↓"
        case .left: return "←"
        case .right: return "→"
        case .ctrlC: return "Ctrl-C"
        case .ctrlD: return "Ctrl-D"
        case .ctrlZ: return "Ctrl-Z"
        case .ctrlA: return "Ctrl-A"
        case .ctrlE: return "Ctrl-E"
        }
    }
}

enum ManagedTerminalModelError: LocalizedError {
    case missingResult(String)
    case invalidShape(String)

    var errorDescription: String? {
        switch self {
        case .missingResult(let context):
            return "Terminal response is missing result: \(context)"
        case .invalidShape(let context):
            return "Terminal response has an invalid shape: \(context)"
        }
    }
}

extension ManagedTerminalList {
    init(json: JSONValue?) throws {
        guard let object = json?.objectValue else {
            throw ManagedTerminalModelError.missingResult("terminal/list")
        }
        self.tmuxVersion = terminalString(object, "tmuxVersion", "tmux_version") ?? ""
        self.sessions = try (terminalArray(object, "sessions") ?? []).map { try ManagedTerminalSession(json: $0) }
        self.windows = try (terminalArray(object, "windows") ?? []).map { try ManagedTerminalWindow(json: $0) }
        self.panes = try (terminalArray(object, "panes") ?? []).map { try ManagedTerminalPane(json: $0) }
        if let paneJSON = object["createdPane"] ?? object["created_pane"] ?? object["selectedPane"] ?? object["selected_pane"] {
            self.createdPane = try ManagedTerminalPane(json: paneJSON)
        } else {
            self.createdPane = nil
        }
    }
}

extension ManagedTerminalSession {
    init(json: JSONValue) throws {
        guard let object = json.objectValue else {
            throw ManagedTerminalModelError.invalidShape("session")
        }
        self.id = terminalString(object, "id") ?? ""
        self.name = terminalString(object, "name") ?? ""
        self.windowCount = terminalInt(object, "windowCount", "window_count") ?? 0
        self.attachedCount = terminalInt(object, "attachedCount", "attached_count") ?? 0
        self.createdAt = terminalInt(object, "createdAt", "created_at") ?? 0
    }
}

extension ManagedTerminalWindow {
    init(json: JSONValue) throws {
        guard let object = json.objectValue else {
            throw ManagedTerminalModelError.invalidShape("window")
        }
        self.id = terminalString(object, "id", "windowId", "window_id") ?? ""
        self.sessionId = terminalString(object, "sessionId", "session_id") ?? ""
        self.sessionName = terminalString(object, "sessionName", "session_name") ?? ""
        self.index = terminalInt(object, "index", "windowIndex", "window_index") ?? 0
        self.name = terminalString(object, "name", "windowName", "window_name") ?? ""
        self.active = terminalBool(object, "active") ?? false
        self.paneCount = terminalInt(object, "paneCount", "pane_count", "windowPanes", "window_panes") ?? 0
        self.layout = terminalString(object, "layout") ?? ""
        self.windowKey = terminalString(object, "windowKey", "window_key") ?? ""
    }
}

extension ManagedTerminalPane {
    init(json: JSONValue) throws {
        guard let rawObject = json.objectValue else {
            throw ManagedTerminalModelError.invalidShape("pane")
        }
        let object = terminalNestedObject(rawObject, "pane", "terminalPane", "terminal_pane", "value") ?? rawObject
        let decodedId = terminalString(
            object,
            "id",
            "paneId",
            "pane_id",
            "target",
            "paneKey",
            "pane_key",
            "paneAddress",
            "pane_address"
        ) ?? ""
        self.id = decodedId
        self.paneId = terminalString(object, "paneId", "pane_id", "target") ?? (decodedId.hasPrefix("%") ? decodedId : "")
        self.paneKey = terminalString(object, "paneKey", "pane_key", "paneAddress", "pane_address", "address") ?? ""
        self.target = terminalString(object, "target", "paneId", "pane_id") ?? (paneId.isEmpty ? paneKey : paneId)
        self.sessionId = terminalString(object, "sessionId", "session_id") ?? ""
        self.sessionName = terminalString(object, "sessionName", "session_name", "session") ?? ""
        self.windowId = terminalString(object, "windowId", "window_id") ?? ""
        self.windowIndex = terminalInt(object, "windowIndex", "window_index") ?? 0
        self.windowName = terminalString(object, "windowName", "window_name") ?? ""
        self.paneIndex = terminalInt(object, "paneIndex", "pane_index", "index") ?? 0
        self.title = terminalString(object, "title", "paneTitle", "pane_title") ?? ""
        self.currentCommand = terminalString(object, "currentCommand", "current_command", "paneCurrentCommand", "pane_current_command") ?? ""
        self.cwd = terminalString(object, "cwd", "currentPath", "current_path", "paneCurrentPath", "pane_current_path") ?? ""
        self.cols = terminalInt(object, "cols", "columns", "paneWidth", "pane_width") ?? 0
        self.rows = terminalInt(object, "rows", "paneHeight", "pane_height") ?? 0
        self.active = terminalBool(object, "active", "paneActive", "pane_active") ?? false
        self.dead = terminalBool(object, "dead", "paneDead", "pane_dead") ?? false
    }
}

extension ManagedTerminalSnapshot {
    init(json: JSONValue?) throws {
        guard let object = json?.objectValue else {
            throw ManagedTerminalModelError.missingResult("terminal/snapshot")
        }
        guard let paneJSON = object["pane"] else {
            throw ManagedTerminalModelError.invalidShape("snapshot.pane")
        }
        self.pane = try ManagedTerminalPane(json: paneJSON)
        self.content = terminalString(object, "content") ?? ""
        self.capturedAt = terminalString(object, "capturedAt", "captured_at") ?? ""
    }
}

private func terminalString(_ object: [String: JSONValue], _ keys: String...) -> String? {
    for key in keys {
        if let value = object[key]?.stringValue {
            return value
        }
        if let value = object[key]?.intValue {
            return String(value)
        }
        if let value = object[key]?.doubleValue {
            return String(value)
        }
        if let value = object[key]?.boolValue {
            return value ? "true" : "false"
        }
    }
    return nil
}

private func terminalInt(_ object: [String: JSONValue], _ keys: String...) -> Int? {
    for key in keys {
        if let value = object[key]?.intValue {
            return value
        }
        if let text = object[key]?.stringValue, let value = Int(text) {
            return value
        }
    }
    return nil
}

private func terminalBool(_ object: [String: JSONValue], _ keys: String...) -> Bool? {
    for key in keys {
        if let value = object[key]?.boolValue {
            return value
        }
        if let text = object[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if ["1", "true", "yes"].contains(text) { return true }
            if ["0", "false", "no"].contains(text) { return false }
        }
    }
    return nil
}

private func terminalArray(_ object: [String: JSONValue], _ keys: String...) -> [JSONValue]? {
    for key in keys {
        if let value = object[key]?.arrayValue {
            return value
        }
    }
    return nil
}

private func terminalNestedObject(_ object: [String: JSONValue], _ keys: String...) -> [String: JSONValue]? {
    for key in keys {
        if let value = object[key]?.objectValue {
            return value
        }
    }
    return nil
}
