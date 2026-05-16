// FILE: CodexService+Terminal.swift
// Purpose: Bridge RPC helpers for managed terminal mode.
// Layer: Service
// Exports: CodexService terminal operations
// Depends on: Foundation, TerminalModels, JSONValue, RPCMessage

import Foundation

private let terminalStreamMessageLimit = 1_500

extension CodexService {
    var selectedTerminalPane: ManagedTerminalPane? {
        guard let selectedTerminalPaneId = normalizedTerminalTarget(selectedTerminalPaneId) else {
            return terminalPanes.first { !$0.requestTarget.isEmpty }
        }
        return terminalPanes.first { $0.matches(target: selectedTerminalPaneId) }
            ?? terminalPanes.first { !$0.requestTarget.isEmpty }
    }

    var selectedTerminalPaneTarget: String? {
        if let target = normalizedTerminalTarget(selectedTerminalPane?.requestTarget) {
            return target
        }
        return normalizedTerminalTarget(selectedTerminalPaneId)
    }

    @discardableResult
    func refreshTerminalList(
        showLoading: Bool = true,
        recordError: Bool = true
    ) async throws -> ManagedTerminalList {
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
            if recordError {
                terminalLastErrorMessage = error.localizedDescription
            }
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
        storeTerminalSnapshot(snapshot, aliases: [paneId])
        upsertTerminalPane(snapshot.pane)
        terminalLastErrorMessage = nil
        return snapshot
    }

    @discardableResult
    func refreshTerminalSnapshot(
        paneId: String? = nil,
        preserveAnsi: Bool = false,
        joinWrapped: Bool = true,
        viewportOnly: Bool = false
    ) async throws -> ManagedTerminalSnapshot {
        let targetPaneId = normalizedTerminalTarget(paneId)
            ?? selectedTerminalPaneTarget
            ?? ""
        guard !targetPaneId.isEmpty else {
            throw CodexServiceError.invalidInput("Select a terminal pane first.")
        }

        var params: RPCObject = ["paneId": .string(targetPaneId)]
        if preserveAnsi {
            params["preserveAnsi"] = .bool(true)
        }
        if !joinWrapped {
            params["joinWrapped"] = .bool(false)
        }
        if viewportOnly {
            params["viewportOnly"] = .bool(true)
        }

        let response = try await sendRequest(
            method: "terminal/snapshot",
            params: .object(params),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "Terminal snapshot timed out while reading the pane."
        )
        let snapshot = try ManagedTerminalSnapshot(json: response.result)
        storeTerminalSnapshot(snapshot, aliases: [targetPaneId])
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
        try await sendTerminalKeyValue(key.rawValue, paneId: paneId)
    }

    func sendTerminalKeyValue(_ key: String, paneId: String? = nil) async throws {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedKey.isEmpty else { return }
        try await sendTerminalInput(
            .object(["kind": .string("key"), "key": .string(normalizedKey)]),
            paneId: paneId
        )
    }

    func sendTerminalData(_ data: Data, paneId: String? = nil) async throws {
        guard !data.isEmpty else { return }
        try await sendTerminalInput(
            .object([
                "kind": .string("bytes"),
                "base64": .string(data.base64EncodedString()),
            ]),
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
        openVisible: Bool = false,
        visibleApp: String? = nil
    ) async throws -> ManagedTerminalList {
        var params: RPCObject = ["cwd": .string(cwd)]
        if let name, !name.isEmpty { params["name"] = .string(name) }
        if let command, !command.isEmpty { params["command"] = .string(command) }
        if let cols { params["cols"] = .integer(cols) }
        if let rows { params["rows"] = .integer(rows) }
        if openVisible { params["openVisible"] = .bool(true) }
        if let visibleApp, !visibleApp.isEmpty { params["visibleApp"] = .string(visibleApp) }

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
        terminalPanes.removeAll { $0.matches(target: targetPaneId) }
        terminalSnapshotsByPaneId.removeValue(forKey: targetPaneId)
        terminalSnapshotsByPaneId.removeValue(forKey: selectedTerminalPaneId ?? "")
        if let selectedTarget = normalizedTerminalTarget(selectedTerminalPaneId),
           !terminalPanes.contains(where: { $0.matches(target: selectedTarget) }) {
            selectedTerminalPaneId = terminalPanes.first?.requestTarget
        }
    }

    func killTerminalSession(_ sessionName: String) async throws {
        let normalizedSession = sessionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSession.isEmpty else {
            throw CodexServiceError.invalidInput("Select a tmux session first.")
        }
        let selectedWasInSession = selectedTerminalPane?.sessionName == normalizedSession
        _ = try await sendRequest(
            method: "terminal/kill",
            params: .object(["sessionName": .string(normalizedSession)]),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "Terminal session close timed out on the Mac bridge."
        )
        terminalPanes.removeAll { $0.sessionName == normalizedSession }
        for key in Array(terminalSnapshotsByPaneId.keys) {
            if terminalPanes.allSatisfy({ !$0.matches(target: key) }) {
                terminalSnapshotsByPaneId.removeValue(forKey: key)
            }
        }
        if selectedWasInSession {
            selectedTerminalPaneId = terminalPanes.first?.requestTarget
        }
    }

    func openVisibleTerminalPane(_ paneId: String? = nil, visibleApp: String? = nil) async throws {
        let targetPaneId = try resolveTerminalPaneId(paneId)
        var params: RPCObject = ["paneId": .string(targetPaneId)]
        if let visibleApp, !visibleApp.isEmpty {
            params["visibleApp"] = .string(visibleApp)
        }
        _ = try await sendRequest(
            method: "terminal/openVisible",
            params: .object(params),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "Opening the terminal on Mac timed out."
        )
        terminalLastErrorMessage = nil
    }

    @discardableResult
    func startTerminalStream(
        paneId: String? = nil,
        cols: Int? = nil,
        rows: Int? = nil,
        replay: Bool = true,
        replayViewportOnly: Bool = false
    ) async throws -> TerminalStreamStartResponse {
        let targetPaneId = try resolveTerminalPaneId(paneId)
        var params: RPCObject = [
            "paneId": .string(targetPaneId),
            "replay": .bool(replay),
        ]
        if replayViewportOnly { params["replayViewportOnly"] = .bool(true) }
        if let cols { params["cols"] = .integer(cols) }
        if let rows { params["rows"] = .integer(rows) }

        let response = try await sendRequest(
            method: "terminal/stream/start",
            params: .object(params),
            timeoutNanoseconds: 8_000_000_000,
            timeoutMessage: "Terminal stream timed out while attaching to the pane."
        )
        let stream = try TerminalStreamStartResponse(json: response.result)
        if terminalStreamMessagesByStreamId[stream.streamId] == nil {
            terminalStreamMessagesByStreamId[stream.streamId] = []
        }
        let existingStatus = terminalStreamStatusByStreamId[stream.streamId]
        terminalStreamStatusByStreamId[stream.streamId] = TerminalStreamRuntimeStatus(
            streamId: stream.streamId,
            paneId: stream.paneId,
            status: existingStatus?.status ?? stream.status,
            lastSeq: existingStatus?.lastSeq ?? 0,
            lastMessage: existingStatus?.lastMessage
        )
        terminalStreamRevision += 1
        terminalLastErrorMessage = nil
        return stream
    }

    func stopTerminalStream(streamId: String? = nil, paneId: String? = nil) async throws {
        var params: RPCObject = [:]
        if let streamId, !streamId.isEmpty { params["streamId"] = .string(streamId) }
        if let paneId, !paneId.isEmpty { params["paneId"] = .string(paneId) }
        _ = try await sendRequest(
            method: "terminal/stream/stop",
            params: .object(params),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "Terminal stream stop timed out."
        )
    }

    func replayTerminalStream(streamId: String) async throws {
        _ = try await sendRequest(
            method: "terminal/stream/replay",
            params: .object(["streamId": .string(streamId)]),
            timeoutNanoseconds: 5_000_000_000,
            timeoutMessage: "Terminal stream replay timed out."
        )
    }

    func stopAllTerminalStreams() async {
        let streamIds = Array(terminalStreamStatusByStreamId.keys)
        for streamId in streamIds where !streamId.isEmpty {
            try? await stopTerminalStream(streamId: streamId)
        }
        clearTerminalStreamState()
    }

    func clearTerminalStreamState() {
        guard !terminalStreamMessagesByStreamId.isEmpty || !terminalStreamStatusByStreamId.isEmpty else {
            return
        }
        terminalStreamMessagesByStreamId.removeAll()
        terminalStreamStatusByStreamId.removeAll()
        terminalStreamRevision += 1
    }

    func handleTerminalStreamEvent(_ paramsObject: IncomingParamsObject?) {
        guard let message = TerminalStreamMessage(json: paramsObject) else {
            return
        }
        let previousStatus = terminalStreamStatusByStreamId[message.streamId]
        guard message.seq > (previousStatus?.lastSeq ?? 0) else {
            return
        }

        var messages = terminalStreamMessagesByStreamId[message.streamId] ?? []
        messages.append(message)
        if messages.count > terminalStreamMessageLimit {
            messages.removeSubrange(0..<(messages.count - terminalStreamMessageLimit))
        }
        terminalStreamMessagesByStreamId[message.streamId] = messages

        terminalStreamStatusByStreamId[message.streamId] = TerminalStreamRuntimeStatus(
            streamId: message.streamId,
            paneId: message.paneId,
            status: terminalStreamStatusText(for: message),
            lastSeq: message.seq,
            lastMessage: message.message ?? message.reason ?? message.status
        )
        terminalStreamRevision += 1
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
           sortedPanes.contains(where: { $0.matches(target: selectedTerminalPaneId) }) {
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

    private func storeTerminalSnapshot(_ snapshot: ManagedTerminalSnapshot, aliases: [String] = []) {
        let keys = [
            snapshot.pane.paneId,
            snapshot.pane.paneKey,
            snapshot.pane.target,
            snapshot.pane.requestTarget,
            snapshot.pane.paneAddress,
        ] + aliases
        for key in keys.compactMap(normalizedTerminalTarget) {
            terminalSnapshotsByPaneId[key] = snapshot
        }
    }

    private func normalizedTerminalTarget(_ value: String?) -> String? {
        let target = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !target.isEmpty,
              target != "unknown",
              target != ":",
              target != ":.",
              target != "::",
              !target.hasPrefix(":"),
              !target.hasSuffix(":"),
              !target.hasSuffix(".") else {
            return nil
        }
        return target
    }

    private func tmuxNumericId(_ value: String) -> Int {
        let digits = value.filter(\.isNumber)
        return Int(digits) ?? Int.min
    }

    private func terminalStreamStatusText(for message: TerminalStreamMessage) -> String {
        switch message.type {
        case .ready:
            return "ready"
        case .output:
            return "live"
        case .replayStart:
            return "replay"
        case .replayEnd, .heartbeat:
            return "live"
        case .error:
            return "error"
        case .exit:
            return "exited"
        case .resizeAck:
            return "resized"
        case .inputAck:
            return "input"
        case .title:
            return "title"
        case .cwd:
            return "cwd"
        case .bell:
            return "bell"
        }
    }
}
