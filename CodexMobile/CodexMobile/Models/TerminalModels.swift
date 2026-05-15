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
        firstUsableTarget(paneId, target, normalizedPaneKey, synthesizedPaneAddress, id) ?? ""
    }

    var paneAddress: String {
        firstUsableTarget(normalizedPaneKey, synthesizedPaneAddress, paneId, target, id) ?? "unknown"
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

    private func firstUsableTarget(_ values: String?...) -> String? {
        values
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: isUsableTerminalTarget)
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
        let sessions = try (terminalArray(object, "sessions") ?? []).map { try ManagedTerminalSession(json: $0) }
        let windows = try (terminalArray(object, "windows") ?? []).map { try ManagedTerminalWindow(json: $0) }
        let panes = try (terminalArray(object, "panes") ?? []).map { try ManagedTerminalPane(json: $0) }
        self.tmuxVersion = terminalString(object, "tmuxVersion", "tmux_version") ?? ""
        self.sessions = sessions
        self.windows = windows
        self.panes = repairTerminalPanes(panes, windows: windows, sessions: sessions)
        if let paneJSON = object["createdPane"] ?? object["created_pane"] ?? object["selectedPane"] ?? object["selected_pane"] {
            let createdPane = try ManagedTerminalPane(json: paneJSON)
            self.createdPane = createdPane.requestTarget.isEmpty
                ? repairTerminalPane(createdPane, window: windows.first, session: sessions.first, fallbackIndex: 0)
                : createdPane
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
        let root = JSONValue.object(rawObject)
        let fields = terminalFieldArray(rawObject) ?? terminalFieldArray(object)

        let decodedId = terminalPaneString(
            object,
            root: root,
            fields: fields,
            fieldIndex: 5,
            "id",
            "paneId",
            "pane_id",
            "target",
            "paneKey",
            "pane_key",
            "paneAddress",
            "pane_address"
        ) ?? ""
        let decodedPaneId = terminalPaneString(
            object,
            root: root,
            fields: fields,
            fieldIndex: 5,
            "paneId",
            "pane_id",
            "target"
        ) ?? (decodedId.hasPrefix("%") ? decodedId : "")
        let decodedSessionName = terminalPaneString(
            object,
            root: root,
            fields: fields,
            fieldIndex: 1,
            "sessionName",
            "session_name",
            "session"
        ) ?? ""
        let decodedWindowIndex = terminalPaneInt(
            object,
            root: root,
            fields: fields,
            fieldIndex: 3,
            "windowIndex",
            "window_index"
        ) ?? 0
        let decodedPaneIndex = terminalPaneInt(
            object,
            root: root,
            fields: fields,
            fieldIndex: 6,
            "paneIndex",
            "pane_index",
            "index"
        ) ?? 0
        let decodedPaneKey = terminalPaneString(
            object,
            root: root,
            fields: fields,
            fieldIndex: nil,
            "paneKey",
            "pane_key",
            "paneAddress",
            "pane_address",
            "address"
        ) ?? (decodedSessionName.isEmpty ? "" : "\(decodedSessionName):\(decodedWindowIndex).\(decodedPaneIndex)")

        self.id = decodedId
        self.paneId = decodedPaneId
        self.paneKey = decodedPaneKey
        self.target = terminalPaneString(object, root: root, fields: fields, fieldIndex: 5, "target", "paneId", "pane_id")
            ?? (decodedPaneId.isEmpty ? decodedPaneKey : decodedPaneId)
        self.sessionId = terminalPaneString(object, root: root, fields: fields, fieldIndex: 0, "sessionId", "session_id") ?? ""
        self.sessionName = decodedSessionName
        self.windowId = terminalPaneString(object, root: root, fields: fields, fieldIndex: 2, "windowId", "window_id") ?? ""
        self.windowIndex = decodedWindowIndex
        self.windowName = terminalPaneString(object, root: root, fields: fields, fieldIndex: 4, "windowName", "window_name") ?? ""
        self.paneIndex = decodedPaneIndex
        self.title = terminalPaneString(object, root: root, fields: fields, fieldIndex: 7, "title", "paneTitle", "pane_title") ?? ""
        self.currentCommand = terminalPaneString(object, root: root, fields: fields, fieldIndex: 8, "currentCommand", "current_command", "paneCurrentCommand", "pane_current_command") ?? ""
        self.cwd = terminalPaneString(object, root: root, fields: fields, fieldIndex: 9, "cwd", "currentPath", "current_path", "paneCurrentPath", "pane_current_path") ?? ""
        self.cols = terminalPaneInt(object, root: root, fields: fields, fieldIndex: 10, "cols", "columns", "paneWidth", "pane_width") ?? 0
        self.rows = terminalPaneInt(object, root: root, fields: fields, fieldIndex: 11, "rows", "paneHeight", "pane_height") ?? 0
        self.active = terminalPaneBool(object, root: root, fields: fields, fieldIndex: 12, "active", "paneActive", "pane_active") ?? false
        self.dead = terminalPaneBool(object, root: root, fields: fields, fieldIndex: 13, "dead", "paneDead", "pane_dead") ?? false
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
    terminalString(object, keys)
}

private func terminalString(_ object: [String: JSONValue], _ keys: [String]) -> String? {
    for key in keys {
        if let value = terminalString(from: object[key]) {
            return value
        }
    }
    return nil
}

private func terminalInt(_ object: [String: JSONValue], _ keys: String...) -> Int? {
    terminalInt(object, keys)
}

private func terminalInt(_ object: [String: JSONValue], _ keys: [String]) -> Int? {
    for key in keys {
        if let value = terminalInt(from: object[key]) {
            return value
        }
    }
    return nil
}

private func terminalBool(_ object: [String: JSONValue], _ keys: String...) -> Bool? {
    terminalBool(object, keys)
}

private func terminalBool(_ object: [String: JSONValue], _ keys: [String]) -> Bool? {
    for key in keys {
        if let value = terminalBool(from: object[key]) {
            return value
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

private func terminalPaneString(
    _ object: [String: JSONValue],
    root: JSONValue,
    fields: [JSONValue]?,
    fieldIndex: Int?,
    _ keys: String...
) -> String? {
    terminalString(object, keys)
        ?? terminalStringDeep(root, keys)
        ?? terminalFieldString(fields, fieldIndex)
}

private func terminalPaneInt(
    _ object: [String: JSONValue],
    root: JSONValue,
    fields: [JSONValue]?,
    fieldIndex: Int?,
    _ keys: String...
) -> Int? {
    terminalInt(object, keys)
        ?? terminalIntDeep(root, keys)
        ?? terminalFieldInt(fields, fieldIndex)
}

private func terminalPaneBool(
    _ object: [String: JSONValue],
    root: JSONValue,
    fields: [JSONValue]?,
    fieldIndex: Int?,
    _ keys: String...
) -> Bool? {
    terminalBool(object, keys)
        ?? terminalBoolDeep(root, keys)
        ?? terminalFieldBool(fields, fieldIndex)
}

private func terminalStringDeep(_ root: JSONValue, _ keys: [String], maxDepth: Int = 5) -> String? {
    guard maxDepth >= 0 else { return nil }
    switch root {
    case .object(let object):
        let normalizedKeys = Set(keys.map(normalizedTerminalJSONKey))
        for (key, value) in object where normalizedKeys.contains(normalizedTerminalJSONKey(key)) {
            if let text = terminalString(from: value) {
                return text
            }
        }
        for value in object.values {
            if let text = terminalStringDeep(value, keys, maxDepth: maxDepth - 1) {
                return text
            }
        }
    case .array(let values):
        for value in values {
            if let text = terminalStringDeep(value, keys, maxDepth: maxDepth - 1) {
                return text
            }
        }
    default:
        return nil
    }
    return nil
}

private func terminalIntDeep(_ root: JSONValue, _ keys: [String], maxDepth: Int = 5) -> Int? {
    terminalStringDeep(root, keys, maxDepth: maxDepth).flatMap { Int($0) }
}

private func terminalBoolDeep(_ root: JSONValue, _ keys: [String], maxDepth: Int = 5) -> Bool? {
    terminalStringDeep(root, keys, maxDepth: maxDepth).flatMap(terminalBool)
}

private func terminalString(from value: JSONValue?) -> String? {
    switch value {
    case .string(let value):
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    case .integer(let value):
        return String(value)
    case .double(let value):
        return String(value)
    case .bool(let value):
        return value ? "true" : "false"
    default:
        return nil
    }
}

private func terminalInt(from value: JSONValue?) -> Int? {
    if let value = value?.intValue {
        return value
    }
    if let text = terminalString(from: value), let value = Int(text) {
        return value
    }
    return nil
}

private func terminalBool(from value: JSONValue?) -> Bool? {
    if let value = value?.boolValue {
        return value
    }
    return terminalString(from: value).flatMap(terminalBool)
}

private func terminalBool(from text: String) -> Bool? {
    let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["1", "true", "yes"].contains(normalized) { return true }
    if ["0", "false", "no"].contains(normalized) { return false }
    return nil
}

private func terminalFieldArray(_ object: [String: JSONValue]) -> [JSONValue]? {
    if let fields = terminalArray(object, "fields", "values", "row") {
        return fields
    }
    let numericValues = (0..<14).map { object[String($0)] ?? .null }
    return numericValues.contains { terminalString(from: $0) != nil } ? numericValues : nil
}

private func terminalFieldString(_ fields: [JSONValue]?, _ index: Int?) -> String? {
    guard let fields, let index, fields.indices.contains(index) else { return nil }
    return terminalString(from: fields[index])
}

private func terminalFieldInt(_ fields: [JSONValue]?, _ index: Int?) -> Int? {
    guard let fields, let index, fields.indices.contains(index) else { return nil }
    return terminalInt(from: fields[index])
}

private func terminalFieldBool(_ fields: [JSONValue]?, _ index: Int?) -> Bool? {
    guard let fields, let index, fields.indices.contains(index) else { return nil }
    return terminalBool(from: fields[index])
}

private func normalizedTerminalJSONKey(_ key: String) -> String {
    key.lowercased().filter { $0.isLetter || $0.isNumber }
}

private func repairTerminalPanes(
    _ panes: [ManagedTerminalPane],
    windows: [ManagedTerminalWindow],
    sessions: [ManagedTerminalSession]
) -> [ManagedTerminalPane] {
    panes.enumerated().map { index, pane in
        guard pane.requestTarget.isEmpty else { return pane }
        return repairTerminalPane(
            pane,
            window: windows.indices.contains(index) ? windows[index] : nil,
            session: sessions.indices.contains(index) ? sessions[index] : nil,
            fallbackIndex: index
        )
    }
}

private func repairTerminalPane(
    _ pane: ManagedTerminalPane,
    window: ManagedTerminalWindow?,
    session: ManagedTerminalSession?,
    fallbackIndex: Int
) -> ManagedTerminalPane {
    let sessionName = firstNonEmptyTerminalString(
        pane.sessionName,
        window?.sessionName,
        session?.name
    ) ?? "mms-\(fallbackIndex + 1)"
    let windowIndex = window?.index ?? pane.windowIndex
    let paneIndex = pane.paneIndex
    let paneAddress = "\(sessionName):\(windowIndex).\(paneIndex)"
    let paneId = isUsableTerminalTarget(pane.paneId) && pane.paneId.hasPrefix("%") ? pane.paneId : ""
    let target = paneId.isEmpty ? paneAddress : paneId

    return ManagedTerminalPane(
        id: firstUsableTerminalString(paneId, pane.id, paneAddress) ?? paneAddress,
        paneId: paneId,
        paneKey: paneAddress,
        target: target,
        sessionId: firstNonEmptyTerminalString(pane.sessionId, window?.sessionId, session?.id) ?? "",
        sessionName: sessionName,
        windowId: firstNonEmptyTerminalString(pane.windowId, window?.id) ?? "",
        windowIndex: windowIndex,
        windowName: firstNonEmptyTerminalString(pane.windowName, window?.name) ?? "",
        paneIndex: paneIndex,
        title: firstNonEmptyTerminalString(pane.title, pane.currentCommand, window?.name) ?? "Terminal",
        currentCommand: pane.currentCommand,
        cwd: pane.cwd,
        cols: pane.cols,
        rows: pane.rows,
        active: pane.active || window?.active == true,
        dead: pane.dead
    )
}

private func firstNonEmptyTerminalString(_ values: String?...) -> String? {
    values
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first { !$0.isEmpty && $0 != "-" }
}

private func firstUsableTerminalString(_ values: String?...) -> String? {
    values
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: isUsableTerminalTarget)
}

private func isUsableTerminalTarget(_ value: String) -> Bool {
    let target = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !target.isEmpty,
          target != "unknown",
          target != ":",
          target != ":.",
          target != "::",
          !target.hasPrefix(":"),
          !target.hasSuffix(":"),
          !target.hasSuffix(".") else {
        return false
    }
    return true
}
