// FILE: SwiftTerminalPaneHeuristics.swift
// Purpose: Keeps Terminal pane scoring and replay heuristics out of the main Swift terminal view.
// Layer: View utility
// Exports: SwiftTerminalPaneHeuristics
// Depends on: Foundation, ManagedTerminalPane

import Foundation

enum SwiftTerminalPaneHeuristics {
    static func isInternalBridgePane(_ pane: ManagedTerminalPane) -> Bool {
        pane.sessionName == "mms-remote-swiftterm-bridge"
    }

    static func preferredDefaultPane(in panes: [ManagedTerminalPane]) -> ManagedTerminalPane? {
        panes.max { lhs, rhs in
            let lhsScore = defaultScore(lhs)
            let rhsScore = defaultScore(rhs)
            if lhsScore != rhsScore { return lhsScore < rhsScore }
            return tmuxObjectNumber(lhs.requestTarget) < tmuxObjectNumber(rhs.requestTarget)
        }
    }

    static func defaultScore(_ pane: ManagedTerminalPane) -> Int {
        let haystack = [
            pane.title,
            pane.currentCommand,
            pane.windowName,
            pane.sessionName,
            pane.cwd,
        ].joined(separator: " ").lowercased()
        let command = pane.currentCommand.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let shellCommands = Set(["", "sh", "bash", "zsh", "fish", "tmux", "login"])
        var score = pane.active ? 20 : 0

        if command == "python" && pane.title.contains("✳") { score += 520 }
        if haystack.contains("claude") || haystack.contains("codex") { score += 460 }
        if !shellCommands.contains(command) { score += 260 }
        if !pane.cwd.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 30 }
        return score
    }

    static func shouldUseViewportReplay(_ pane: ManagedTerminalPane?) -> Bool {
        guard let pane else { return false }
        let text = [
            pane.title,
            pane.currentCommand,
            pane.windowName,
            pane.sessionName,
        ].joined(separator: " ").lowercased()
        // tmux history capture is not an ANSI replay; TUI agents need viewport replay.
        let agentMarkers = ["claude", "codex", "opencode", "gemini", "kimi", "minimax", "deepseek", "glm"]
        if agentMarkers.contains(where: { text.contains($0) }) {
            return true
        }
        let tuiMarkers = ["vim", "nvim", "less", "top", "htop", "btop", "nano"]
        return tuiMarkers.contains { text.contains($0) }
    }

    private static func tmuxObjectNumber(_ value: String) -> Int {
        Int(value.filter(\.isNumber)) ?? Int.min
    }
}
