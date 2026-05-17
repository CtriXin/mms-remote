// FILE: SwiftTerminalTypes.swift
// Purpose: Shared Swift Terminal support types kept out of the main hub view.
// Layer: View support

import SwiftUI

enum SwiftTerminalCloseRequest: Identifiable {
    case pane(ManagedTerminalPane)
    case session(ManagedTerminalPane)

    var id: String {
        switch self {
        case .pane(let pane): return "pane-\(pane.requestTarget)"
        case .session(let pane): return "session-\(pane.sessionName)"
        }
    }

    var title: String {
        switch self {
        case .pane:
            return LocalizationManager.shared.localized("terminal.dialog.close_title")
        case .session:
            return LocalizationManager.shared.localized("terminal.dialog.close_session_title")
        }
    }

    var buttonTitle: String {
        switch self {
        case .pane(let pane):
            return String(format: LocalizationManager.shared.localized("terminal.close_pane"), pane.displayTitle)
        case .session(let pane):
            return String(format: LocalizationManager.shared.localized("terminal.close_session"), pane.sessionName)
        }
    }

    var message: String {
        switch self {
        case .pane(let pane):
            return String(format: LocalizationManager.shared.localized("terminal.dialog.close_message"), pane.paneKey)
        case .session(let pane):
            return String(format: LocalizationManager.shared.localized("terminal.dialog.close_session_message"), pane.sessionName)
        }
    }

    func matches(_ target: String?) -> Bool {
        switch self {
        case .pane(let pane):
            return pane.matches(target: target)
        case .session(let pane):
            guard let target else { return false }
            return pane.sessionName == target || target.hasPrefix("\(pane.sessionName):")
        }
    }
}

struct SwiftTerminalTheme {
    let isDark: Bool
    let shellBackground: Color
    let panelBackground: Color
    let terminalSurface: Color
    let terminalInputBackground: Color
    let primaryText: Color
    let secondaryText: Color
    let buttonBackground: Color
    let buttonPressedBackground: Color
    let buttonText: Color
    let selectedChipText: Color
    let accent: Color
    let terminalText: Color
    let terminalAccent: Color
    let border: Color

    static func resolve(systemScheme: ColorScheme, useDarkTerminalCanvas: Bool) -> SwiftTerminalTheme {
        let terminalSurface = useDarkTerminalCanvas
            ? Color(red: 0.12, green: 0.12, blue: 0.17)
            : Color(.systemBackground)
        let terminalText = useDarkTerminalCanvas
            ? Color(red: 0.86, green: 0.88, blue: 0.96)
            : Color(.label)
        let terminalAccent = useDarkTerminalCanvas
            ? Color(red: 0.72, green: 0.94, blue: 0.60)
            : Color(red: 0.21, green: 0.58, blue: 0.38)
        if systemScheme == .dark {
            return SwiftTerminalTheme(
                isDark: true,
                shellBackground: Color(.systemGroupedBackground),
                panelBackground: Color(.secondarySystemGroupedBackground),
                terminalSurface: terminalSurface,
                terminalInputBackground: Color(.secondarySystemGroupedBackground),
                primaryText: Color(.label),
                secondaryText: Color(.secondaryLabel),
                buttonBackground: Color(.tertiarySystemFill),
                buttonPressedBackground: Color(.secondarySystemFill),
                buttonText: Color(.label),
                selectedChipText: Color(red: 0.02, green: 0.05, blue: 0.04),
                accent: Color(red: 0.64, green: 0.93, blue: 0.55),
                terminalText: terminalText,
                terminalAccent: terminalAccent,
                border: Color.white.opacity(0.10)
            )
        }

        return SwiftTerminalTheme(
            isDark: useDarkTerminalCanvas,
            shellBackground: Color(.systemGroupedBackground),
            panelBackground: Color(.secondarySystemGroupedBackground),
            terminalSurface: terminalSurface,
            terminalInputBackground: Color(.secondarySystemGroupedBackground),
            primaryText: Color(.label),
            secondaryText: Color(.secondaryLabel),
            buttonBackground: Color(.tertiarySystemFill),
            buttonPressedBackground: Color(.secondarySystemFill),
            buttonText: Color(.label),
            selectedChipText: Color.white,
            accent: Color(red: 0.21, green: 0.58, blue: 0.38),
            terminalText: terminalText,
            terminalAccent: terminalAccent,
            border: Color.black.opacity(0.08)
        )
    }
}

enum SwiftTerminalRendererMode: String, CaseIterable, Identifiable {
    case stable
    case swiftTerm

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .stable: return LocalizationManager.shared.localized("swift_terminal.renderer_stable")
        case .swiftTerm: return LocalizationManager.shared.localized("swift_terminal.renderer_swiftterm")
        }
    }

    var localizedShortTitle: String {
        switch self {
        case .stable: return LocalizationManager.shared.localized("swift_terminal.renderer_stable_short")
        case .swiftTerm: return LocalizationManager.shared.localized("swift_terminal.renderer_swiftterm_short")
        }
    }
}

enum SwiftTerminalShortcutProfile: String, CaseIterable, Identifiable {
    case compact
    case agent
    case shell
    case mac
    case custom

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .compact: return LocalizationManager.shared.localized("swift_terminal.shortcuts_compact")
        case .agent: return LocalizationManager.shared.localized("swift_terminal.shortcuts_agent")
        case .shell: return LocalizationManager.shared.localized("swift_terminal.shortcuts_shell")
        case .mac: return LocalizationManager.shared.localized("swift_terminal.shortcuts_mac")
        case .custom: return LocalizationManager.shared.localized("swift_terminal.shortcuts_custom")
        }
    }

    var localizedShortTitle: String {
        switch self {
        case .compact: return LocalizationManager.shared.localized("swift_terminal.shortcuts_compact_short")
        case .agent: return LocalizationManager.shared.localized("swift_terminal.shortcuts_agent_short")
        case .shell: return LocalizationManager.shared.localized("swift_terminal.shortcuts_shell_short")
        case .mac: return LocalizationManager.shared.localized("swift_terminal.shortcuts_mac_short")
        case .custom: return LocalizationManager.shared.localized("swift_terminal.shortcuts_custom_short")
        }
    }
}

enum SwiftTerminalShortcutAction: String, CaseIterable {
    case copy
    case paste
    case focus
    case hideKeyboard = "hide-keyboard"
    case top
    case bottom
    case reset

    init?(_ value: String) {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        self.init(rawValue: normalized)
    }
}

enum SwiftTerminalDirectionalKey: CaseIterable, Identifiable {
    case left
    case up
    case down
    case right

    var id: String { keyValue }

    var glyph: String {
        switch self {
        case .left: return "←"
        case .up: return "↑"
        case .down: return "↓"
        case .right: return "→"
        }
    }

    var keyValue: String {
        switch self {
        case .left: return ManagedTerminalKey.left.rawValue
        case .up: return ManagedTerminalKey.up.rawValue
        case .down: return ManagedTerminalKey.down.rawValue
        case .right: return ManagedTerminalKey.right.rawValue
        }
    }

    static let defaultTap = SwiftTerminalDirectionalKey.right

    static func direction(for translation: CGSize, threshold: CGFloat = 13) -> SwiftTerminalDirectionalKey? {
        guard max(abs(translation.width), abs(translation.height)) >= threshold else { return nil }
        if abs(translation.width) >= abs(translation.height) {
            return translation.width < 0 ? .left : .right
        }
        return translation.height < 0 ? .up : .down
    }
}

enum SwiftTerminalChordModifier: String, CaseIterable, Identifiable, Hashable {
    case command
    case control
    case option
    case shift

    var id: String { rawValue }

    var label: String {
        switch self {
        case .command: return "⌘"
        case .control: return "⌃"
        case .option: return "⌥"
        case .shift: return "⇧"
        }
    }

    var keyPrefix: String { rawValue }
}

enum SwiftTerminalChordKeyPage: String, CaseIterable, Identifiable {
    case letters
    case digits
    case symbols
    case navigation
    case functionKeys

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .letters: return LocalizationManager.shared.localized("swift_terminal.chord_page_letters")
        case .digits: return LocalizationManager.shared.localized("swift_terminal.chord_page_digits")
        case .symbols: return LocalizationManager.shared.localized("swift_terminal.chord_page_symbols")
        case .navigation: return LocalizationManager.shared.localized("swift_terminal.chord_page_navigation")
        case .functionKeys: return LocalizationManager.shared.localized("swift_terminal.chord_page_functions")
        }
    }

    var keys: [SwiftTerminalChordKey] {
        switch self {
        case .letters: return SwiftTerminalChordKey.letters
        case .digits: return SwiftTerminalChordKey.digits
        case .symbols: return SwiftTerminalChordKey.symbols
        case .navigation: return SwiftTerminalChordKey.navigation
        case .functionKeys: return SwiftTerminalChordKey.functionKeys
        }
    }
}

struct SwiftTerminalChordKey: Identifiable, Hashable {
    let label: String
    let value: String
    let textValue: String?

    var id: String { value }

    static let letters: [SwiftTerminalChordKey] = (65...90).compactMap { value in
        guard let scalar = UnicodeScalar(UInt32(value)) else { return nil }
        let label = String(Character(scalar))
        return SwiftTerminalChordKey(label: label, value: label.lowercased(), textValue: label.lowercased())
    }

    static let digits: [SwiftTerminalChordKey] = (0...9).map { digit in
        let value = String(digit)
        return SwiftTerminalChordKey(label: value, value: value, textValue: value)
    }

    static let symbols: [SwiftTerminalChordKey] = [
        .init(label: "=", value: "=", textValue: "="),
        .init(label: "-", value: "-", textValue: "-"),
        .init(label: "+", value: "+", textValue: "+"),
        .init(label: "_", value: "_", textValue: "_"),
        .init(label: "/", value: "/", textValue: "/"),
        .init(label: ".", value: ".", textValue: "."),
        .init(label: ",", value: ",", textValue: ","),
        .init(label: ";", value: ";", textValue: ";"),
        .init(label: ":", value: ":", textValue: ":"),
        .init(label: "'", value: "'", textValue: "'"),
        .init(label: "\"", value: "\"", textValue: "\""),
        .init(label: "[", value: "[", textValue: "["),
        .init(label: "]", value: "]", textValue: "]"),
        .init(label: "\\", value: "\\", textValue: "\\"),
        .init(label: "`", value: "`", textValue: "`"),
        .init(label: "<", value: "<", textValue: "<"),
        .init(label: ">", value: ">", textValue: ">"),
        .init(label: "?", value: "?", textValue: "?"),
        .init(label: "~", value: "~", textValue: "~"),
        .init(label: "Space", value: "space", textValue: " "),
    ]

    static let navigation: [SwiftTerminalChordKey] = [
        .init(label: "tab", value: "tab", textValue: nil),
        .init(label: "⇧⇥", value: "shift-tab", textValue: nil),
        .init(label: "ESC", value: "escape", textValue: nil),
        .init(label: "return", value: "enter", textValue: nil),
        .init(label: "delete", value: "backspace", textValue: nil),
        .init(label: "⌦", value: "delete", textValue: nil),
        .init(label: "home", value: "home", textValue: nil),
        .init(label: "end", value: "end", textValue: nil),
        .init(label: "pg up", value: "page-up", textValue: nil),
        .init(label: "pg dn", value: "page-down", textValue: nil),
        .init(label: "←", value: "left", textValue: nil),
        .init(label: "→", value: "right", textValue: nil),
        .init(label: "↑", value: "up", textValue: nil),
        .init(label: "↓", value: "down", textValue: nil),
    ]

    static let functionKeys: [SwiftTerminalChordKey] = (1...12).map { number in
        SwiftTerminalChordKey(label: "F\(number)", value: "f\(number)", textValue: nil)
    }
}

struct SwiftTerminalShortcut: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case key
        case text
        case bytes
        case action
    }

    let label: String
    let kind: Kind
    let value: String

    var id: String { "\(kind.rawValue):\(label):\(value)" }
    var pinId: String { "\(kind.rawValue):\(value)" }

    static let compactProfile: [SwiftTerminalShortcut] = [
        .key("ESC", .escape),
        .key("tab", .tab),
        .key("return", .enter),
        .key("delete", .backspace),
        .key("↑", .up),
        .key("↓", .down),
        .key("←", .left),
        .key("→", .right),
    ]

    static let agentProfile: [SwiftTerminalShortcut] = [
        .key("ESC", .escape),
        .key("⌃C", .ctrlC),
        .key("⌃D", .ctrlD),
        .key("⌃Z", .ctrlZ),
        .key("tab", .tab),
        .key("return", .enter),
        .key("delete", .backspace),
        .text("/", "/"),
        .text("-", "-"),
        .key("↑", .up),
        .key("↓", .down),
    ]

    static let shellProfile: [SwiftTerminalShortcut] = [
        .key("⌃C", .ctrlC),
        .rawKey("⌃L", "ctrl-l"),
        .rawKey("⌃R", "ctrl-r"),
        .rawKey("⌃U", "ctrl-u"),
        .rawKey("⌃W", "ctrl-w"),
        .rawKey("⌃K", "ctrl-k"),
        .key("⌃A", .ctrlA),
        .key("⌃E", .ctrlE),
        .key("home", .home),
        .key("end", .end),
        .key("pg up", .pageUp),
        .key("pg dn", .pageDown),
        .key("←", .left),
        .key("→", .right),
        .key("return", .enter),
    ]

    static let macProfile: [SwiftTerminalShortcut] = [
        .action("⌘C", .copy),
        .action("⌘V", .paste),
        .rawKey("⌘K", "ctrl-l"),
        .rawKey("⌥←", "option-left"),
        .rawKey("⌥→", "option-right"),
        .rawKey("⇧⇥", "shift-tab"),
        .rawKey("⌦", "delete"),
        .rawKey("F1", "f1"),
        .rawKey("F2", "f2"),
        .rawKey("F3", "f3"),
        .rawKey("F4", "f4"),
        .rawKey("F5", "f5"),
        .rawKey("F6", "f6"),
        .rawKey("F7", "f7"),
        .rawKey("F8", "f8"),
        .rawKey("F9", "f9"),
        .rawKey("F10", "f10"),
        .rawKey("F11", "f11"),
        .rawKey("F12", "f12"),
    ]

    static let defaultCustomJSON = """
    [
      {"label":"ESC","kind":"key","value":"escape"},
      {"label":"⌘C","kind":"action","value":"copy"},
      {"label":"⌥←","kind":"key","value":"option-left"},
      {"label":"⌘⌃=","kind":"key","value":"command-control-="},
      {"label":"⌃C","kind":"key","value":"ctrl-c"},
      {"label":"cd ..","kind":"text","value":"cd ..\\n"}
    ]
    """

    static let defaultPinnedShortcuts: [SwiftTerminalShortcut] = [
        .key("ESC", .escape),
        .key("return", .enter),
        .key("delete", .backspace),
        .key("↑", .up),
        .key("↓", .down),
        .key("←", .left),
        .key("→", .right),
        .key("⌃C", .ctrlC),
    ]

    static let defaultPinnedIds = defaultPinnedShortcuts
        .map(\.pinId)
        .joined(separator: "\n")

    static func key(_ label: String, _ key: ManagedTerminalKey) -> SwiftTerminalShortcut {
        SwiftTerminalShortcut(label: label, kind: .key, value: key.rawValue)
    }

    static func rawKey(_ label: String, _ value: String) -> SwiftTerminalShortcut {
        SwiftTerminalShortcut(label: label, kind: .key, value: value)
    }

    static func text(_ label: String, _ value: String) -> SwiftTerminalShortcut {
        SwiftTerminalShortcut(label: label, kind: .text, value: value)
    }

    static func action(_ label: String, _ action: SwiftTerminalShortcutAction) -> SwiftTerminalShortcut {
        SwiftTerminalShortcut(label: label, kind: .action, value: action.rawValue)
    }
}

struct SwiftTerminalKeyButtonStyle: ButtonStyle {
    let theme: SwiftTerminalTheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.caption(weight: .semibold))
            .foregroundStyle(theme.buttonText.opacity(configuration.isPressed ? 0.62 : 1.0))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .multilineTextAlignment(.center)
            .frame(minWidth: 44, minHeight: 32)
            .padding(.horizontal, 8)
            .background(configuration.isPressed ? theme.buttonPressedBackground : theme.buttonBackground, in: Capsule())
    }
}

struct SwiftTerminalModifierButtonStyle: ButtonStyle {
    let theme: SwiftTerminalTheme
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.caption(weight: .bold))
            .foregroundStyle(isActive ? Color.black : theme.buttonText)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .multilineTextAlignment(.center)
            .frame(minWidth: 58, minHeight: 32)
            .padding(.horizontal, 10)
            .background(
                configuration.isPressed
                    ? theme.accent.opacity(0.72)
                    : (isActive ? theme.accent : theme.buttonBackground),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(isActive ? theme.accent.opacity(0.95) : Color.clear, lineWidth: 2)
            )
    }
}

extension ManagedTerminalKey {
    static func swiftTerminalKeyValue(from value: String) -> String? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let map: [String: String] = [
            "enter": Self.enter.rawValue,
            "return": Self.enter.rawValue,
            "backspace": Self.backspace.rawValue,
            "bs": Self.backspace.rawValue,
            "delete": "delete",
            "del": "delete",
            "tab": Self.tab.rawValue,
            "shift-tab": "shift-tab",
            "shifttab": "shift-tab",
            "backtab": "shift-tab",
            "escape": Self.escape.rawValue,
            "esc": Self.escape.rawValue,
            "up": Self.up.rawValue,
            "down": Self.down.rawValue,
            "left": Self.left.rawValue,
            "right": Self.right.rawValue,
            "home": Self.home.rawValue,
            "end": Self.end.rawValue,
            "pageup": Self.pageUp.rawValue,
            "page-up": Self.pageUp.rawValue,
            "pagedown": Self.pageDown.rawValue,
            "page-down": Self.pageDown.rawValue,
            "pgup": Self.pageUp.rawValue,
            "pgdn": Self.pageDown.rawValue,
            "ctrlc": Self.ctrlC.rawValue,
            "ctrld": Self.ctrlD.rawValue,
            "ctrlz": Self.ctrlZ.rawValue,
            "ctrla": Self.ctrlA.rawValue,
            "ctrle": Self.ctrlE.rawValue,
        ]
        if let key = map[normalized] {
            return key
        }
        if isFunctionKey(normalized) {
            return normalized
        }
        if let compoundKey = compoundModifiedKey(normalized) {
            return compoundKey
        }
        if let suffix = modifiedKeySuffix(normalized, prefixes: ["ctrl", "control", "c"]),
           isValidControlKeySuffix(suffix) {
            return "ctrl-\(suffix)"
        }
        if let suffix = modifiedKeySuffix(normalized, prefixes: ["alt", "option", "meta", "m"]),
           isValidMetaKeySuffix(suffix) {
            return "alt-\(suffix)"
        }
        if let suffix = modifiedKeySuffix(normalized, prefixes: ["shift", "s"]),
           isValidShiftKeySuffix(suffix) {
            return "shift-\(suffix)"
        }
        return nil
    }

    private static func compoundModifiedKey(_ value: String) -> String? {
        let parts = value.split(separator: "-").map(String.init)
        guard parts.count >= 2 else { return nil }

        var modifiers = [String]()
        var index = 0
        while index < parts.count - 1, let modifier = chordModifierPrefix(parts[index]) {
            if !modifiers.contains(modifier) {
                modifiers.append(modifier)
            }
            index += 1
        }

        guard !modifiers.isEmpty, index < parts.count else { return nil }
        let suffix = parts[index...].joined(separator: "-")
        guard isValidChordKeySuffix(suffix) else { return nil }

        let orderedModifiers = ["command", "ctrl", "alt", "shift"].filter { modifiers.contains($0) }
        return (orderedModifiers + [suffix]).joined(separator: "-")
    }

    private static func chordModifierPrefix(_ token: String) -> String? {
        switch token {
        case "command", "cmd": return "command"
        case "control", "ctrl": return "ctrl"
        case "option", "alt", "meta": return "alt"
        case "shift": return "shift"
        default: return nil
        }
    }

    private static func modifiedKeySuffix(_ value: String, prefixes: [String]) -> String? {
        for prefix in prefixes {
            let dashed = "\(prefix)-"
            if value.hasPrefix(dashed) {
                return String(value.dropFirst(dashed.count))
            }
            if value.hasPrefix(prefix), value.count == prefix.count + 1 {
                return String(value.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private static func isFunctionKey(_ value: String) -> Bool {
        guard value.hasPrefix("f"), let number = Int(value.dropFirst()) else { return false }
        return (1...12).contains(number)
    }

    private static func isValidControlKeySuffix(_ suffix: String) -> Bool {
        if suffix.count == 1 {
            return true
        }
        return [
            "left", "right", "up", "down",
            "home", "end", "pageup", "page-up", "pagedown", "page-down",
            "backspace", "delete", "tab", "space",
        ].contains(suffix)
    }

    private static func isValidMetaKeySuffix(_ suffix: String) -> Bool {
        if suffix.count == 1 {
            return true
        }
        return isFunctionKey(suffix)
            || [
                "left", "right", "up", "down",
                "home", "end", "pageup", "page-up", "pagedown", "page-down",
                "backspace", "delete", "tab", "space",
            ].contains(suffix)
    }

    private static func isValidShiftKeySuffix(_ suffix: String) -> Bool {
        isFunctionKey(suffix)
            || ["tab", "left", "right", "up", "down", "home", "end"].contains(suffix)
    }

    private static func isValidChordKeySuffix(_ suffix: String) -> Bool {
        if suffix.count == 1 {
            return true
        }
        return isFunctionKey(suffix)
            || [
                "left", "right", "up", "down",
                "home", "end", "pageup", "page-up", "pagedown", "page-down",
                "backspace", "delete", "tab", "space", "enter", "return", "escape", "esc",
            ].contains(suffix)
    }
}
