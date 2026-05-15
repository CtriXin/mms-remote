// FILE: CodexService+Terminal.swift
// Purpose: Bridge RPC helpers for managed terminal mode.
// Layer: Service
// Exports: CodexService terminal operations
// Depends on: Foundation, TerminalModels, JSONValue, RPCMessage

import Foundation

extension CodexService {
    var selectedTerminalPane: ManagedTerminalPane? {
        guard let selectedTerminalPaneId = normalizedTerminalTarget(selectedTerminalPaneId) else {
            return terminalPanes.first { !$0.requestTarget.isEmpty }
        }
        return terminalPanes.first { pane in
            pane.paneId == selectedTerminalPaneId
                || pane.paneKey == selectedTerminalPaneId
                || pane.target == selectedTerminalPaneId
                || pane.requestTarget == selectedTerminalPaneId
                || pane.paneAddress == selectedTerminalPaneId
        } ?? terminalPanes.first { !$0.requestTarget.isEmpty }
    }

    var selectedTerminalPaneTarget: String? {
        if let target = normalizedTerminalTarget(selectedTerminalPane?.requestTarget) {
            return target
        }
        return normalizedTerminalTarget(selectedTerminalPaneId)
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
        selectedTerminalPaneId = snapshot.pane.requestTarget
        storeTerminalSnapshot(snapshot)
        upsertTerminalPane(snapshot.pane)
        terminalLastErrorMessage = nil
        return snapshot
    }

    @discardableResult
    func refreshTerminalSnapshot(paneId: String? = nil) async throws -> ManagedTerminalSnapshot {
        let targetPaneId = normalizedTerminalTarget(paneId)
            ?? selectedTerminalPaneTarget
            ?? ""
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
        storeTerminalSnapshot(snapshot)
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
        if let createdPane = list.createdPane, !createdPane.requestTarget.isEmpty {
            upsertTerminalPane(createdPane)
            selectedTerminalPaneId = createdPane.requestTarget
        }
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
        terminalPanes.removeAll { paneMatches(pane: $0, target: targetPaneId) }
        terminalSnapshotsByPaneId.removeValue(forKey: targetPaneId)
        terminalSnapshotsByPaneId.removeValue(forKey: selectedTerminalPaneId ?? "")
        if let selectedTarget = normalizedTerminalTarget(selectedTerminalPaneId),
           !terminalPanes.contains(where: { paneMatches(pane: $0, target: selectedTarget) }) {
            selectedTerminalPaneId = terminalPanes.first?.requestTarget
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
        let targetPaneId = normalizedTerminalTarget(paneId)
            ?? selectedTerminalPaneTarget
            ?? ""
        guard !targetPaneId.isEmpty else {
            throw CodexServiceError.invalidInput("Select a terminal pane first.")
        }
        return targetPaneId
    }

    private func applyTerminalList(_ list: ManagedTerminalList) {
        let previousPaneTargets = Set(terminalPanes.map(\.requestTarget).filter { !$0.isEmpty })
        let sortedPanes = sortTerminalPanesByRecent(list.panes).filter { !$0.requestTarget.isEmpty }
        terminalTmuxVersion = list.tmuxVersion
        terminalSessions = sortTerminalSessionsByRecent(list.sessions)
        terminalWindows = sortTerminalWindowsByRecent(list.windows)
        terminalPanes = sortedPanes
        if let newestPane = sortedPanes.first(where: { !previousPaneTargets.contains($0.requestTarget) }) {
            selectedTerminalPaneId = newestPane.requestTarget
            return
        }
        if let selectedTerminalPaneId = normalizedTerminalTarget(selectedTerminalPaneId),
           sortedPanes.contains(where: { paneMatches(pane: $0, target: selectedTerminalPaneId) }) {
            self.selectedTerminalPaneId = selectedTerminalPaneId
        } else {
            selectedTerminalPaneId = sortedPanes.first?.requestTarget
        }
    }

    private func upsertTerminalPane(_ pane: ManagedTerminalPane) {
        let target = pane.requestTarget
        guard !target.isEmpty else { return }
        if let index = terminalPanes.firstIndex(where: { $0.requestTarget == target }) {
            terminalPanes[index] = pane
        } else {
            terminalPanes.append(pane)
        }
        terminalPanes = sortTerminalPanesByRecent(terminalPanes)
    }

    private func sortTerminalSessionsByRecent(_ sessions: [ManagedTerminalSession]) -> [ManagedTerminalSession] {
        sessions.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            let lhsId = tmuxNumericId(lhs.id)
            let rhsId = tmuxNumericId(rhs.id)
            if lhsId != rhsId { return lhsId > rhsId }
            return lhs.name < rhs.name
        }
    }

    private func sortTerminalWindowsByRecent(_ windows: [ManagedTerminalWindow]) -> [ManagedTerminalWindow] {
        windows.sorted { lhs, rhs in
            let lhsId = tmuxNumericId(lhs.id)
            let rhsId = tmuxNumericId(rhs.id)
            if lhsId != rhsId { return lhsId > rhsId }
            if lhs.windowKey != rhs.windowKey { return lhs.windowKey < rhs.windowKey }
            return lhs.name < rhs.name
        }
    }

    private func sortTerminalPanesByRecent(_ panes: [ManagedTerminalPane]) -> [ManagedTerminalPane] {
        panes.sorted { lhs, rhs in
            let lhsId = tmuxNumericId(lhs.requestTarget)
            let rhsId = tmuxNumericId(rhs.requestTarget)
            if lhsId != rhsId { return lhsId > rhsId }
            if lhs.windowIndex != rhs.windowIndex { return lhs.windowIndex > rhs.windowIndex }
            if lhs.paneIndex != rhs.paneIndex { return lhs.paneIndex > rhs.paneIndex }
            return lhs.paneKey < rhs.paneKey
        }
    }

    private func storeTerminalSnapshot(_ snapshot: ManagedTerminalSnapshot) {
        let keys = [
            snapshot.pane.paneId,
            snapshot.pane.paneKey,
            snapshot.pane.target,
            snapshot.pane.requestTarget,
            snapshot.pane.paneAddress,
        ]
        for key in keys.compactMap(normalizedTerminalTarget) {
            terminalSnapshotsByPaneId[key] = snapshot
        }
    }

    private func paneMatches(pane: ManagedTerminalPane, target: String) -> Bool {
        [
            pane.paneId,
            pane.paneKey,
            pane.target,
            pane.requestTarget,
            pane.paneAddress,
        ]
        .compactMap(normalizedTerminalTarget)
        .contains(target)
    }

    private func normalizedTerminalTarget(_ value: String?) -> String? {
        let target = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return target.isEmpty ? nil : target
    }

    private func tmuxNumericId(_ value: String) -> Int {
        let digits = value.filter(\.isNumber)
        return Int(digits) ?? Int.min
    }
}
