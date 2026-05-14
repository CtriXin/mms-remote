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

    var displayTitle: String {
        if !title.isEmpty { return title }
        if !currentCommand.isEmpty { return currentCommand }
        return paneKey
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

    static let empty = ManagedTerminalList(
        tmuxVersion: "",
        sessions: [],
        windows: [],
        panes: []
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
        self.tmuxVersion = object["tmuxVersion"]?.stringValue ?? ""
        self.sessions = try (object["sessions"]?.arrayValue ?? []).map { try ManagedTerminalSession(json: $0) }
        self.windows = try (object["windows"]?.arrayValue ?? []).map { try ManagedTerminalWindow(json: $0) }
        self.panes = try (object["panes"]?.arrayValue ?? []).map { try ManagedTerminalPane(json: $0) }
    }
}

extension ManagedTerminalSession {
    init(json: JSONValue) throws {
        guard let object = json.objectValue else {
            throw ManagedTerminalModelError.invalidShape("session")
        }
        self.id = object["id"]?.stringValue ?? ""
        self.name = object["name"]?.stringValue ?? ""
        self.windowCount = object["windowCount"]?.intValue ?? 0
        self.attachedCount = object["attachedCount"]?.intValue ?? 0
        self.createdAt = object["createdAt"]?.intValue ?? 0
    }
}

extension ManagedTerminalWindow {
    init(json: JSONValue) throws {
        guard let object = json.objectValue else {
            throw ManagedTerminalModelError.invalidShape("window")
        }
        self.id = object["id"]?.stringValue ?? ""
        self.sessionId = object["sessionId"]?.stringValue ?? ""
        self.sessionName = object["sessionName"]?.stringValue ?? ""
        self.index = object["index"]?.intValue ?? 0
        self.name = object["name"]?.stringValue ?? ""
        self.active = object["active"]?.boolValue ?? false
        self.paneCount = object["paneCount"]?.intValue ?? 0
        self.layout = object["layout"]?.stringValue ?? ""
        self.windowKey = object["windowKey"]?.stringValue ?? ""
    }
}

extension ManagedTerminalPane {
    init(json: JSONValue) throws {
        guard let object = json.objectValue else {
            throw ManagedTerminalModelError.invalidShape("pane")
        }
        self.id = object["id"]?.stringValue ?? object["paneId"]?.stringValue ?? ""
        self.paneId = object["paneId"]?.stringValue ?? id
        self.paneKey = object["paneKey"]?.stringValue ?? ""
        self.target = object["target"]?.stringValue ?? paneId
        self.sessionId = object["sessionId"]?.stringValue ?? ""
        self.sessionName = object["sessionName"]?.stringValue ?? ""
        self.windowId = object["windowId"]?.stringValue ?? ""
        self.windowIndex = object["windowIndex"]?.intValue ?? 0
        self.windowName = object["windowName"]?.stringValue ?? ""
        self.paneIndex = object["paneIndex"]?.intValue ?? 0
        self.title = object["title"]?.stringValue ?? ""
        self.currentCommand = object["currentCommand"]?.stringValue ?? ""
        self.cwd = object["cwd"]?.stringValue ?? ""
        self.cols = object["cols"]?.intValue ?? 0
        self.rows = object["rows"]?.intValue ?? 0
        self.active = object["active"]?.boolValue ?? false
        self.dead = object["dead"]?.boolValue ?? false
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
        self.content = object["content"]?.stringValue ?? ""
        self.capturedAt = object["capturedAt"]?.stringValue ?? ""
    }
}
