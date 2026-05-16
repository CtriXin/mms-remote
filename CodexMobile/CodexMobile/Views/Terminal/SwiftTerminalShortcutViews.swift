// FILE: SwiftTerminalShortcutViews.swift
// Purpose: Swift Terminal shortcut/key bar UI components.
// Layer: View support

import SwiftUI

struct SwiftTerminalKeyBarView<StableInput: View>: View {
    let isSwiftTermRendererActive: Bool
    @Binding var keyBarExpanded: Bool
    @Binding var bracketedPaste: Bool
    @Binding var fontSize: Double
    let theme: SwiftTerminalTheme
    let pinnedShortcuts: [SwiftTerminalShortcut]
    let displayedActiveShortcuts: [SwiftTerminalShortcut]
    let shortcutProfile: SwiftTerminalShortcutProfile
    let onFocusTerminalInput: () -> Void
    let onHideTerminalKeyboard: () -> Void
    let onSelectPreviousPane: () -> Void
    let onSelectNextPane: () -> Void
    let onToggleKeyBarExpanded: () -> Void
    let onControlModifier: () -> Void
    let onMetaModifier: () -> Void
    let onCopyTerminal: () -> Void
    let onPasteClipboard: () -> Void
    let onOpenChordComposer: () -> Void
    let onOpenPinnedShortcutPicker: () -> Void
    let onSelectShortcutProfile: (SwiftTerminalShortcutProfile) -> Void
    let onOpenShortcutEditor: () -> Void
    let onSendShortcut: (SwiftTerminalShortcut) -> Void
    let stableInput: () -> StableInput

    var body: some View {
        VStack(spacing: 8) {
            if !isSwiftTermRendererActive {
                stableInput()
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(LocalizationManager.shared.localized("swift_terminal.focus"), action: onFocusTerminalInput)
                    Button(LocalizationManager.shared.localized("swift_terminal.hide_keyboard"), action: onHideTerminalKeyboard)
                    Button(LocalizationManager.shared.localized("swift_terminal.previous_pane"), action: onSelectPreviousPane)
                    Button(LocalizationManager.shared.localized("swift_terminal.next_pane"), action: onSelectNextPane)
                    Button(LocalizationManager.shared.localized(keyBarExpanded ? "swift_terminal.hide_keys" : "swift_terminal.show_keys"), action: onToggleKeyBarExpanded)
                }
            }
            .buttonStyle(SwiftTerminalKeyButtonStyle(theme: theme))

            if keyBarExpanded {
                expandedControls
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, keyBarExpanded ? 10 : 8)
        .background(theme.panelBackground)
    }

    private var expandedControls: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if isSwiftTermRendererActive {
                        Button(LocalizationManager.shared.localized("terminal.button.ctrl"), action: onControlModifier)
                        Button(LocalizationManager.shared.localized("terminal.button.alt"), action: onMetaModifier)
                    }
                    Button(LocalizationManager.shared.localized("terminal.button.copy"), action: onCopyTerminal)
                    Button(LocalizationManager.shared.localized("terminal.button.paste"), action: onPasteClipboard)
                    Button(LocalizationManager.shared.localized("swift_terminal.chord_compose"), action: onOpenChordComposer)
                    Button(LocalizationManager.shared.localized("swift_terminal.shortcuts_pin"), action: onOpenPinnedShortcutPicker)
                    shortcutProfileMenu
                }
            }
            .buttonStyle(SwiftTerminalKeyButtonStyle(theme: theme))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                ForEach(pinnedShortcuts) { shortcut in
                    Button(shortcut.label) { onSendShortcut(shortcut) }
                }
            }
            .buttonStyle(SwiftTerminalKeyButtonStyle(theme: theme))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 62), spacing: 8)], spacing: 8) {
                ForEach(displayedActiveShortcuts) { shortcut in
                    Button(shortcut.label) { onSendShortcut(shortcut) }
                }
            }
            .buttonStyle(SwiftTerminalKeyButtonStyle(theme: theme))

            HStack(spacing: 12) {
                Toggle(LocalizationManager.shared.localized("swift_terminal.bracketed_paste"), isOn: $bracketedPaste)
                    .font(AppFont.caption2())
                    .foregroundStyle(theme.secondaryText)
                    .tint(theme.accent)
                Spacer()
                Stepper(value: $fontSize, in: 8...18, step: 1) {
                    Text(String(format: LocalizationManager.shared.localized("swift_terminal.font_size"), Int(fontSize)))
                        .font(AppFont.caption2())
                        .foregroundStyle(theme.secondaryText)
                }
                .tint(theme.accent)
                .frame(maxWidth: 150)
            }
        }
    }

    private var shortcutProfileMenu: some View {
        Menu {
            ForEach(SwiftTerminalShortcutProfile.allCases) { profile in
                Button {
                    onSelectShortcutProfile(profile)
                } label: {
                    Label(profile.localizedTitle, systemImage: profile == shortcutProfile ? "checkmark" : "keyboard")
                }
            }
            Button {
                onOpenShortcutEditor()
            } label: {
                Label(LocalizationManager.shared.localized("swift_terminal.shortcuts_edit"), systemImage: "slider.horizontal.3")
            }
        } label: {
            Text(shortcutProfile.localizedShortTitle)
        }
    }
}

struct SwiftTerminalChordComposerPanel: View {
    let theme: SwiftTerminalTheme
    @Binding var chordPanelHeight: CGFloat
    @Binding var chordPanelDragStartHeight: CGFloat?
    let chordPanelMinHeight: CGFloat
    let chordPanelMaxHeight: CGFloat
    let selectedChordModifiers: Set<SwiftTerminalChordModifier>
    @Binding var selectedChordKeyPage: SwiftTerminalChordKeyPage
    let chordPreviewGlyphText: String
    let chordPreviewValueText: String
    let onClose: () -> Void
    let onToggleModifier: (SwiftTerminalChordModifier) -> Void
    let onSendChordKey: (SwiftTerminalChordKey) -> Void
    let onAppearSuppressKeyboard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(theme.secondaryText.opacity(0.45))
                .frame(width: 48, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 3)
                .gesture(resizeGesture)

            HStack(spacing: 10) {
                Text(chordPreviewGlyphText)
                    .font(AppFont.mono(.headline))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(chordPreviewValueText)
                    .font(AppFont.mono(.caption2))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .foregroundStyle(theme.secondaryText)
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                ForEach(SwiftTerminalChordModifier.allCases) { modifier in
                    chordModifierButton(modifier)
                }
            }

            Picker(LocalizationManager.shared.localized("swift_terminal.chord_sheet_title"), selection: $selectedChordKeyPage) {
                ForEach(SwiftTerminalChordKeyPage.allCases) { page in
                    Text(page.localizedTitle).tag(page)
                }
            }
            .pickerStyle(.segmented)

            ScrollView(.vertical, showsIndicators: true) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 58), spacing: 7)], spacing: 7) {
                    ForEach(selectedChordKeyPage.keys) { key in
                        Button(key.label) { onSendChordKey(key) }
                    }
                }
                .buttonStyle(SwiftTerminalKeyButtonStyle(theme: theme))
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .frame(height: chordPanelHeight)
        .background(theme.panelBackground)
        .onAppear(perform: onAppearSuppressKeyboard)
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                let startHeight = chordPanelDragStartHeight ?? chordPanelHeight
                chordPanelDragStartHeight = startHeight
                chordPanelHeight = min(chordPanelMaxHeight, max(chordPanelMinHeight, startHeight - value.translation.height))
            }
            .onEnded { _ in
                chordPanelDragStartHeight = nil
            }
    }

    private func chordModifierButton(_ modifier: SwiftTerminalChordModifier) -> some View {
        let isSelected = selectedChordModifiers.contains(modifier)
        return Button {
            onToggleModifier(modifier)
        } label: {
            Text(modifier.label)
                .font(AppFont.caption(weight: .bold))
                .foregroundStyle(isSelected ? theme.selectedChipText : theme.buttonText)
                .frame(width: 42, height: 32)
                .background(
                    Capsule()
                        .fill(isSelected ? theme.accent : theme.buttonBackground)
                )
        }
        .buttonStyle(.plain)
    }
}

struct SwiftTerminalShortcutEditorSheet: View {
    @Binding var shortcutEditorDraft: String
    @Binding var shortcutEditorError: String?
    let onClose: () -> Void
    let onApply: () -> Void
    let onReset: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 10) {
                Text(LocalizationManager.shared.localized("swift_terminal.shortcuts_json_hint"))
                    .font(AppFont.caption())
                    .foregroundStyle(.secondary)
                TextEditor(text: $shortcutEditorDraft)
                    .font(AppFont.mono(.caption))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let shortcutEditorError {
                    Text(shortcutEditorError)
                        .font(AppFont.caption2())
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
            .navigationTitle(LocalizationManager.shared.localized("swift_terminal.shortcuts_custom"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizationManager.shared.localized("common.cancel"), action: onClose)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(LocalizationManager.shared.localized("common.apply"), action: onApply)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(LocalizationManager.shared.localized("swift_terminal.shortcuts_reset"), action: onReset)
                }
            }
        }
    }
}

struct SwiftTerminalPinnedShortcutPickerSheet: View {
    let theme: SwiftTerminalTheme
    let pinnedShortcuts: [SwiftTerminalShortcut]
    let unpinnedSelectableShortcuts: [SwiftTerminalShortcut]
    let onTogglePinnedShortcut: (SwiftTerminalShortcut) -> Void
    let onMovePinnedShortcuts: (IndexSet, Int) -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(pinnedShortcuts) { shortcut in
                        shortcutRow(shortcut, isPinned: true)
                    }
                    .onMove(perform: onMovePinnedShortcuts)
                } header: {
                    Text(LocalizationManager.shared.localized("swift_terminal.shortcuts_pinned"))
                } footer: {
                    Text(LocalizationManager.shared.localized("swift_terminal.shortcuts_pinned_hint"))
                }
                Section {
                    ForEach(unpinnedSelectableShortcuts) { shortcut in
                        shortcutRow(shortcut, isPinned: false)
                    }
                } header: {
                    Text(LocalizationManager.shared.localized("swift_terminal.shortcuts_available"))
                }
            }
            .navigationTitle(LocalizationManager.shared.localized("swift_terminal.shortcuts_pin"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizationManager.shared.localized("common.close"), action: onClose)
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
            }
        }
    }

    private func shortcutRow(_ shortcut: SwiftTerminalShortcut, isPinned: Bool) -> some View {
        Button {
            onTogglePinnedShortcut(shortcut)
        } label: {
            HStack(spacing: 12) {
                Text(shortcut.label)
                    .font(AppFont.mono(.body))
                    .foregroundStyle(theme.primaryText)
                    .frame(minWidth: 84, alignment: .leading)
                Text(shortcut.value)
                    .font(AppFont.caption())
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: isPinned ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isPinned ? theme.accent : theme.secondaryText)
            }
            .contentShape(Rectangle())
        }
    }
}
