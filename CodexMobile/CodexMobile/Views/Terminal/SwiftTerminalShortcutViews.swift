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
    let isControlModifierLatched: Bool
    let isMetaModifierLatched: Bool
    let onFocusTerminalInput: () -> Void
    let onHideTerminalKeyboard: () -> Void
    let onSendTab: () -> Void
    let onSendDirectionalKey: (SwiftTerminalDirectionalKey) -> Void
    let onSendEscape: () -> Void
    let onSendInterrupt: () -> Void
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

            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button(LocalizationManager.shared.localized("swift_terminal.focus"), action: onFocusTerminalInput)
                        Button(LocalizationManager.shared.localized("swift_terminal.hide_keyboard"), action: onHideTerminalKeyboard)
                        if isSwiftTermRendererActive {
                            modifierButton(LocalizationManager.shared.localized("terminal.button.ctrl"), isActive: isControlModifierLatched, action: onControlModifier)
                            modifierButton(LocalizationManager.shared.localized("terminal.button.alt"), isActive: isMetaModifierLatched, action: onMetaModifier)
                        }
                        Button("Tab", action: onSendTab)
                        SwiftTerminalDirectionPadButton(theme: theme, onSend: onSendDirectionalKey)
                        Button("ESC", action: onSendEscape)
                        Button("⌃C", action: onSendInterrupt)
                        Button(LocalizationManager.shared.localized("terminal.button.paste"), action: onPasteClipboard)
                    }
                }
                Button(keyBarExpanded ? "↓" : "↑", action: onToggleKeyBarExpanded)
                    .accessibilityLabel(LocalizationManager.shared.localized(keyBarExpanded ? "swift_terminal.hide_keys" : "swift_terminal.show_keys"))
            }
            .buttonStyle(SwiftTerminalKeyButtonStyle(theme: theme))

            if keyBarExpanded {
                expandedControls
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, keyBarExpanded ? 10 : 8)
        .background(.regularMaterial)
    }

    private var expandedControls: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button(LocalizationManager.shared.localized("terminal.button.copy"), action: onCopyTerminal)
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

    private func modifierButton(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(isActive ? "\(title) ON" : title)
        }
        .buttonStyle(SwiftTerminalModifierButtonStyle(theme: theme, isActive: isActive))
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

struct SwiftTerminalDirectionPadButton: View {
    let theme: SwiftTerminalTheme
    let onSend: (SwiftTerminalDirectionalKey) -> Void

    @State private var activeDirection: SwiftTerminalDirectionalKey?
    @State private var didSendDuringGesture = false
    @State private var isPressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Capsule()
                .fill(isPressed ? theme.buttonPressedBackground : theme.buttonBackground)
            directionLabels
            Text(activeDirection?.glyph ?? SwiftTerminalDirectionalKey.defaultTap.glyph)
                .font(AppFont.caption(weight: .bold))
                .foregroundStyle(activeDirection == nil ? theme.buttonText : theme.accent)
        }
        .frame(width: 52, height: 32)
        .overlay(
            Capsule()
                .stroke(activeDirection == nil ? theme.border : theme.accent.opacity(0.88), lineWidth: activeDirection == nil ? 1 : 2)
        )
        .contentShape(Capsule())
        .highPriorityGesture(directionGesture)
        .accessibilityLabel(LocalizationManager.shared.localized("swift_terminal.direction_pad"))
        .accessibilityHint(LocalizationManager.shared.localized("swift_terminal.direction_pad_hint"))
        .onDisappear(perform: stopRepeating)
        .animation(.easeOut(duration: 0.12), value: activeDirection)
        .animation(.easeOut(duration: 0.12), value: isPressed)
    }

    private var directionLabels: some View {
        ZStack {
            Text("↑").offset(y: -9)
            Text("↓").offset(y: 9)
            Text("←").offset(x: -15)
            Text("→").offset(x: 15)
        }
        .font(AppFont.caption2(weight: .semibold))
        .foregroundStyle(theme.secondaryText.opacity(activeDirection == nil ? 0.48 : 0.2))
    }

    private var directionGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                isPressed = true
                guard let direction = SwiftTerminalDirectionalKey.direction(for: value.translation) else { return }
                guard activeDirection != direction else { return }
                activeDirection = direction
                didSendDuringGesture = true
                onSend(direction)
                startRepeating(direction)
            }
            .onEnded { value in
                defer { resetGestureState() }
                guard !didSendDuringGesture else { return }
                let direction = SwiftTerminalDirectionalKey.direction(for: value.translation) ?? .defaultTap
                onSend(direction)
            }
    }

    private func startRepeating(_ direction: SwiftTerminalDirectionalKey) {
        stopRepeating()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard !Task.isCancelled else { return }
            while !Task.isCancelled {
                onSend(direction)
                try? await Task.sleep(nanoseconds: 85_000_000)
                guard !Task.isCancelled else { return }
            }
        }
    }

    private func resetGestureState() {
        stopRepeating()
        activeDirection = nil
        didSendDuringGesture = false
        isPressed = false
    }

    private func stopRepeating() {
        repeatTask?.cancel()
        repeatTask = nil
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
