// FILE: TerminalPreferences.swift
// Purpose: Shared terminal preference models used by Settings and terminal views.
// Layer: Model
// Exports: TerminalFontFamily, TerminalVisibleAppPreference

import Foundation

enum TerminalFontFamily: String, CaseIterable, Identifiable {
    static let storageKey = "terminal.fontFamily"
    static let defaultStoredRawValue = TerminalFontFamily.hackNerdFont.rawValue

    case hackNerdFont
    case jetBrainsMono
    case geistMono
    case systemMono

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .hackNerdFont: return "Hack Nerd Font"
        case .jetBrainsMono: return "JetBrains Mono"
        case .geistMono: return "Geist Mono"
        case .systemMono: return LocalizationManager.shared.localized("terminal.settings.font_system")
        }
    }

    static var current: TerminalFontFamily {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let family = TerminalFontFamily(rawValue: raw) else {
            return .hackNerdFont
        }
        return family
    }
}

enum TerminalVisibleAppPreference: String, CaseIterable, Identifiable {
    static let storageKey = "terminal.visibleApp"
    static let defaultStoredRawValue = TerminalVisibleAppPreference.auto.rawValue

    case auto
    case ghostty
    case iterm
    case terminal

    var id: String { rawValue }

    var rpcValue: String {
        rawValue
    }

    var localizedTitle: String {
        switch self {
        case .auto: return LocalizationManager.shared.localized("terminal.settings.visible_auto")
        case .ghostty: return "Ghostty"
        case .iterm: return "iTerm2"
        case .terminal: return "Terminal.app"
        }
    }

    static var current: TerminalVisibleAppPreference {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let app = TerminalVisibleAppPreference(rawValue: raw) else {
            return .auto
        }
        return app
    }
}
