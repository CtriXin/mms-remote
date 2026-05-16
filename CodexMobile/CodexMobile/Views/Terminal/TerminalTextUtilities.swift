// FILE: TerminalTextUtilities.swift
// Purpose: Shared terminal text cleanup helpers for Swift and legacy terminal renderers.
// Layer: View utility
// Exports: TerminalTextUtilities
// Depends on: Foundation

import Foundation

enum TerminalTextUtilities {
    static func trimBlankEdges(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.count > 1,
              lines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
              lines.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            lines.removeFirst()
        }
        while lines.count > 1,
              lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true,
              lines.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    static func sanitizeDisplayText(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.reserveCapacity(text.unicodeScalars.count)
        for scalar in text.unicodeScalars {
            if isUnsupportedDisplayScalar(scalar) {
                scalars.append(UnicodeScalar(32)!)
            } else if isControlScalar(scalar) {
                continue
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    static func appendSanitizedCharacter(_ character: Character, to output: inout String) {
        for scalar in String(character).unicodeScalars {
            if isUnsupportedDisplayScalar(scalar) {
                output.append(" ")
            } else if isControlScalar(scalar) {
                continue
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
    }

    static func isControlScalar(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        return value < 0x20 && value != 0x0A && value != 0x09
    }

    static func isUnsupportedDisplayScalar(_ scalar: UnicodeScalar) -> Bool {
        let value = scalar.value
        return value == 0xFFFD
            || (0xE000...0xF8FF).contains(value)
            || (0xF0000...0xFFFFD).contains(value)
            || (0x100000...0x10FFFD).contains(value)
    }
}
