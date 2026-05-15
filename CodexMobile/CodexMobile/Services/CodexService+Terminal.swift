// FILE: CodexService+Terminal.swift
// Purpose: Bridge RPC helpers for managed terminal mode.
// Layer: Service
// Exports: CodexService terminal operations
// Depends on: Foundation, TerminalModels, JSONValue, RPCMessage

import Foundation

extension CodexService {
    var selectedTerminalPane: ManagedTerminalPane? {
        guard let selectedTerminalPaneId else { return nil }
        return terminalPanes.first { $0.paneId == selectedTerminalPaneId || $0.paneKey == selectedTerminalPaneId }
    }

    @discardableResult
    func refreshTerminalList(showLoading: Bool = true) async throws -> ManagedTerminalList {
        if showLoading { isLoadingTerminals = true }
        defer {
            if showLoading { isLoadingTerminals = false }
        }

        do {
            let response = try await sendRequest(
                method: "terminal/list",
                params: .object([:]),
                timeoutNanoseconds: 8_000_000_000,
                timeoutMessage: "Terminal list timed out while contacting the Mac bridge."
            )
            let list = try ManagedTerminalList(json: response.result)
            applyTerminalList(list)
            terminalLastErrorMessage = nil
            return list
        } catch {
            terminalLastErrorMessage = error.localizedDescription
            throw error
        }
    }

    @discardableResult
    func attachTerminalPane(_ paneId: String) async throws -> ManagedTerminalSnapshot {
        let response = try await sendRequest(
            method: "terminal/attach",
            params: .object(["paneId": .string(paneId)]),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "Terminal attach timed out while reading the pane snapshot."
        )
        let snapshot = try ManagedTerminalSnapshot(json: response.result)
        selectedTerminalPaneId = snapshot.pane.paneId
        terminalSnapshotsByPaneId[snapshot.pane.paneId] = snapshot
        upsertTerminalPane(snapshot.pane)
        terminalLastErrorMessage = nil
        return snapshot
    }

    @discardableResult
    func refreshTerminalSnapshot(paneId: String? = nil) async throws -> ManagedTerminalSnapshot {
        let targetPaneId = paneId ?? selectedTerminalPaneId ?? ""
        guard !targetPaneId.isEmpty else {
            throw CodexServiceError.invalidInput("Select a terminal pane first.")
        }

        let response = try await sendRequest(
            method: "terminal/snapshot",
            params: .object(["paneId": .string(targetPaneId)]),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "Terminal snapshot timed out while reading the pane."
        )
        let snapshot = try ManagedTerminalSnapshot(json: response.result)
        terminalSnapshotsByPaneId[snapshot.pane.paneId] = snapshot
        upsertTerminalPane(snapshot.pane)
        terminalLastErrorMessage = nil
        return snapshot
    }

    func sendTerminalText(_ text: String, paneId: String? = nil) async throws {
        guard !text.isEmpty else { return }
        try await sendTerminalInput(
            .object(["kind": .string("text"), "text": .string(text)]),
            paneId: paneId
        )
    }

    func sendTerminalKey(_ key: ManagedTerminalKey, paneId: String? = nil) async throws {
        try await sendTerminalInput(
            .object(["kind": .string("key"), "key": .string(key.rawValue)]),
            paneId: paneId
        )
    }

    @discardableResult
    func createManagedTerminal(
        name: String? = nil,
        cwd: String,
        command: String? = nil,
        cols: Int? = nil,
        rows: Int? = nil,
        openVisible: Bool = false
    ) async throws -> ManagedTerminalList {
        var params: RPCObject = ["cwd": .string(cwd)]
        if let name, !name.isEmpty { params["name"] = .string(name) }
        if let command, !command.isEmpty { params["command"] = .string(command) }
        if let cols { params["cols"] = .integer(cols) }
        if let rows { params["rows"] = .integer(rows) }
        if openVisible { params["openVisible"] = .bool(true) }

        let response = try await sendRequest(
            method: "terminal/create",
            params: .object(params),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "Creating the terminal timed out on the Mac bridge."
        )
        let list = try ManagedTerminalList(json: response.result)
        applyTerminalList(list)
        terminalLastErrorMessage = nil
        return list
    }

    func resizeTerminalPane(paneId: String? = nil, cols: Int, rows: Int) async throws {
        let targetPaneId = try resolveTerminalPaneId(paneId)
        _ = try await sendRequest(
            method: "terminal/resize",
            params: .object([
                "paneId": .string(targetPaneId),
                "cols": .integer(cols),
                "rows": .integer(rows),
            ]),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "Terminal resize timed out on the Mac bridge."
        )
    }

    func killTerminalPane(_ paneId: String? = nil) async throws {
        let targetPaneId = try resolveTerminalPaneId(paneId)
        _ = try await sendRequest(
            method: "terminal/kill",
            params: .object(["paneId": .string(targetPaneId)]),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "Terminal close timed out on the Mac bridge."
        )
        terminalPanes.removeAll { $0.paneId == targetPaneId || $0.paneKey == targetPaneId }
        terminalSnapshotsByPaneId.removeValue(forKey: targetPaneId)
        if selectedTerminalPaneId == targetPaneId {
            selectedTerminalPaneId = terminalPanes.first?.paneId
        }
    }

    func openVisibleTerminalPane(_ paneId: String? = nil) async throws {
        let targetPaneId = try resolveTerminalPaneId(paneId)
        _ = try await sendRequest(
            method: "terminal/openVisible",
            params: .object(["paneId": .string(targetPaneId)]),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "Opening the terminal on Mac timed out."
        )
        terminalLastErrorMessage = nil
    }

    private func sendTerminalInput(_ input: JSONValue, paneId: String?) async throws {
        let targetPaneId = try resolveTerminalPaneId(paneId)
        _ = try await sendRequest(
            method: "terminal/input",
            params: .object([
                "paneId": .string(targetPaneId),
                "input": input,
            ]),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "Terminal input timed out on the Mac bridge."
        )
    }

    private func resolveTerminalPaneId(_ paneId: String?) throws -> String {
        let targetPaneId = paneId ?? selectedTerminalPaneId ?? ""
        guard !targetPaneId.isEmpty else {
            throw CodexServiceError.invalidInput("Select a terminal pane first.")
        }
        return targetPaneId
    }

    private func applyTerminalList(_ list: ManagedTerminalList) {
        terminalTmuxVersion = list.tmuxVersion
        terminalSessions = list.sessions
        terminalWindows = list.windows
        terminalPanes = list.panes
        if let selectedTerminalPaneId,
           !list.panes.contains(where: { $0.paneId == selectedTerminalPaneId || $0.paneKey == selectedTerminalPaneId }) {
            self.selectedTerminalPaneId = list.panes.first?.paneId
        } else if selectedTerminalPaneId == nil {
            selectedTerminalPaneId = list.panes.first?.paneId
        }
    }

    private func upsertTerminalPane(_ pane: ManagedTerminalPane) {
        if let index = terminalPanes.firstIndex(where: { $0.paneId == pane.paneId }) {
            terminalPanes[index] = pane
        } else {
            terminalPanes.append(pane)
        }
    }
}
