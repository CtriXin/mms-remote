// FILE: SwiftTerminalANSIRenderer.swift
// Purpose: Converts terminal ANSI text into display-safe plain and attributed text.
// Layer: View utility
// Exports: SwiftTerminalANSIRenderer
// Depends on: SwiftUI, TerminalTextUtilities

import SwiftUI

enum SwiftTerminalANSIRenderer {
    static func plainText(from text: String) -> String {
        TerminalTextUtilities.sanitizeDisplayText(stripEscapeSequences(from: text))
    }

    static func attributedText(from text: String, defaultForeground: Color) -> AttributedString {
        let source = trimBlankEdgesPreservingANSI(text)
        let plain = TerminalTextUtilities.trimBlankEdges(plainText(from: source))
        let defaultStyle = SwiftTerminalANSIStyle(foreground: defaultForeground)
        guard !plain.isEmpty else {
            return styledRun(" ", style: defaultStyle)
        }

        var output = AttributedString()
        var style = defaultStyle
        var buffer = ""
        var index = source.startIndex

        while index < source.endIndex {
            if source[index] == "\u{001B}" {
                appendStyledBuffer(&buffer, style: style, to: &output)
                index = applyEscape(in: source, from: index, style: &style, defaultForeground: defaultForeground)
                continue
            }

            TerminalTextUtilities.appendSanitizedCharacter(source[index], to: &buffer)
            index = source.index(after: index)
        }

        appendStyledBuffer(&buffer, style: style, to: &output)
        return output.characters.isEmpty ? styledRun(" ", style: defaultStyle) : output
    }

    private static func appendStyledBuffer(
        _ buffer: inout String,
        style: SwiftTerminalANSIStyle,
        to output: inout AttributedString
    ) {
        guard !buffer.isEmpty else { return }
        output += styledRun(buffer, style: style)
        buffer.removeAll(keepingCapacity: true)
    }

    private static func styledRun(_ text: String, style: SwiftTerminalANSIStyle) -> AttributedString {
        var run = AttributedString(text)
        run.foregroundColor = style.foreground
        if let background = style.background {
            run.backgroundColor = background
        }
        if style.bold {
            run.inlinePresentationIntent = .stronglyEmphasized
        }
        return run
    }

    private static func stripEscapeSequences(from text: String) -> String {
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\u{001B}" {
                index = consumeEscape(in: text, from: index)
                continue
            }
            TerminalTextUtilities.appendSanitizedCharacter(text[index], to: &output)
            index = text.index(after: index)
        }
        return output
    }

    private static func trimBlankEdgesPreservingANSI(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        func hasVisibleText(_ line: String) -> Bool {
            !plainText(from: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        while lines.count > 1,
              lines.first.map({ !hasVisibleText($0) }) == true,
              lines.contains(where: hasVisibleText) {
            lines.removeFirst()
        }
        while lines.count > 1,
              lines.last.map({ !hasVisibleText($0) }) == true,
              lines.contains(where: hasVisibleText) {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func applyEscape(
        in text: String,
        from start: String.Index,
        style: inout SwiftTerminalANSIStyle,
        defaultForeground: Color
    ) -> String.Index {
        var index = text.index(after: start)
        guard index < text.endIndex else { return index }
        guard text[index] == "[" else {
            return consumeEscape(in: text, from: start)
        }

        index = text.index(after: index)
        let parameterStart = index
        while index < text.endIndex {
            let value = text[index].unicodeScalars.first?.value ?? 0
            if (0x40...0x7E).contains(value) {
                let parameters = String(text[parameterStart..<index])
                let final = text[index]
                let next = text.index(after: index)
                if final == "m" {
                    applySGRParameters(parameters, to: &style, defaultForeground: defaultForeground)
                }
                return next
            }
            index = text.index(after: index)
        }
        return index
    }

    private static func consumeEscape(in text: String, from start: String.Index) -> String.Index {
        var index = text.index(after: start)
        guard index < text.endIndex else { return index }

        if text[index] == "[" {
            index = text.index(after: index)
            while index < text.endIndex {
                let value = text[index].unicodeScalars.first?.value ?? 0
                index = text.index(after: index)
                if (0x40...0x7E).contains(value) {
                    return index
                }
            }
            return index
        }

        if text[index] == "]" {
            index = text.index(after: index)
            while index < text.endIndex {
                if text[index] == "\u{0007}" {
                    return text.index(after: index)
                }
                if text[index] == "\u{001B}" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\\" {
                        return text.index(after: next)
                    }
                }
                index = text.index(after: index)
            }
            return index
        }

        return text.index(after: index)
    }

    private static func applySGRParameters(
        _ parameters: String,
        to style: inout SwiftTerminalANSIStyle,
        defaultForeground: Color
    ) {
        let normalized = parameters.replacingOccurrences(of: ":", with: ";")
        let values = normalized
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }
        let codes = values.isEmpty ? [0] : values
        var index = 0

        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0:
                style = SwiftTerminalANSIStyle(foreground: defaultForeground)
            case 1:
                style.bold = true
            case 22:
                style.bold = false
            case 30...37:
                style.foreground = ansiColor(code - 30, bright: false)
            case 90...97:
                style.foreground = ansiColor(code - 90, bright: true)
            case 39:
                style.foreground = defaultForeground
            case 40...47:
                style.background = ansiColor(code - 40, bright: false).opacity(0.70)
            case 100...107:
                style.background = ansiColor(code - 100, bright: true).opacity(0.70)
            case 49:
                style.background = nil
            case 38, 48:
                let isForeground = code == 38
                if let parsed = extendedANSIColor(from: codes, startingAt: index + 1) {
                    if isForeground {
                        style.foreground = parsed.color
                    } else {
                        style.background = parsed.color.opacity(0.70)
                    }
                    index = parsed.nextIndex - 1
                }
            default:
                break
            }
            index += 1
        }
    }

    private static func extendedANSIColor(from codes: [Int], startingAt index: Int) -> (color: Color, nextIndex: Int)? {
        guard index < codes.count else { return nil }
        if codes[index] == 5, index + 1 < codes.count {
            return (xterm256Color(codes[index + 1]), index + 2)
        }
        if codes[index] == 2, index + 3 < codes.count {
            return (
                Color(
                    red: Double(max(0, min(255, codes[index + 1]))) / 255.0,
                    green: Double(max(0, min(255, codes[index + 2]))) / 255.0,
                    blue: Double(max(0, min(255, codes[index + 3]))) / 255.0
                ),
                index + 4
            )
        }
        return nil
    }

    private static func xterm256Color(_ value: Int) -> Color {
        let clamped = max(0, min(255, value))
        if clamped < 16 {
            return ansiColor(clamped % 8, bright: clamped >= 8)
        }
        if clamped <= 231 {
            let offset = clamped - 16
            let red = offset / 36
            let green = (offset % 36) / 6
            let blue = offset % 6
            return Color(
                red: xtermColorComponent(red),
                green: xtermColorComponent(green),
                blue: xtermColorComponent(blue)
            )
        }
        let gray = Double(8 + (clamped - 232) * 10) / 255.0
        return Color(red: gray, green: gray, blue: gray)
    }

    private static func xtermColorComponent(_ value: Int) -> Double {
        value == 0 ? 0.0 : Double(55 + value * 40) / 255.0
    }

    private static func ansiColor(_ index: Int, bright: Bool) -> Color {
        let normal = [
            Color(red: 0.18, green: 0.20, blue: 0.23),
            Color(red: 0.86, green: 0.25, blue: 0.28),
            Color(red: 0.45, green: 0.78, blue: 0.36),
            Color(red: 0.87, green: 0.66, blue: 0.28),
            Color(red: 0.33, green: 0.56, blue: 0.93),
            Color(red: 0.76, green: 0.42, blue: 0.89),
            Color(red: 0.30, green: 0.78, blue: 0.83),
            Color(red: 0.82, green: 0.91, blue: 0.86),
        ]
        let brightColors = [
            Color(red: 0.45, green: 0.49, blue: 0.54),
            Color(red: 1.00, green: 0.38, blue: 0.40),
            Color(red: 0.64, green: 0.93, blue: 0.55),
            Color(red: 1.00, green: 0.81, blue: 0.41),
            Color(red: 0.46, green: 0.70, blue: 1.00),
            Color(red: 0.92, green: 0.58, blue: 1.00),
            Color(red: 0.50, green: 0.93, blue: 0.95),
            Color(red: 0.95, green: 0.98, blue: 0.92),
        ]
        return (bright ? brightColors : normal)[max(0, min(7, index))]
    }
}

private struct SwiftTerminalANSIStyle {
    var foreground: Color
    var background: Color? = nil
    var bold = false
}
