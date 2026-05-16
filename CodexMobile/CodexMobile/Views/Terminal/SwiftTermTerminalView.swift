// FILE: SwiftTermTerminalView.swift
// Purpose: SwiftUI bridge for SwiftTerm-backed managed tmux panes.
// Layer: View
// Exports: SwiftTermTerminalView
// Depends on: SwiftUI, UIKit, SwiftTerm, AppFont

import SwiftTerm
import SwiftUI
import UIKit

struct SwiftTermTerminalView: UIViewRepresentable {
    let paneTarget: String?
    let snapshotText: String
    let isConnected: Bool
    let focusRequestID: Int
    let copyRequestID: Int
    let pasteRequestID: Int
    let controlModifierRequestID: Int
    let metaModifierRequestID: Int
    let onSendData: (Data) -> Void
    let onResize: (Int, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSendData: onSendData, onResize: onResize)
    }

    func makeUIView(context: Context) -> TerminalView {
        let terminalView = MMSMobileTerminalView(frame: .zero, font: AppFont.terminalMonoUIFont(size: 12, textStyle: .caption1))
        context.coordinator.attach(terminalView)
        configure(terminalView)
        return terminalView
    }

    func updateUIView(_ terminalView: TerminalView, context: Context) {
        context.coordinator.onSendData = onSendData
        context.coordinator.onResize = onResize
        configure(terminalView)
        terminalView.font = AppFont.terminalMonoUIFont(size: 12, textStyle: .caption1)
        context.coordinator.applyCommands(
            to: terminalView,
            focusRequestID: focusRequestID,
            copyRequestID: copyRequestID,
            pasteRequestID: pasteRequestID,
            controlModifierRequestID: controlModifierRequestID,
            metaModifierRequestID: metaModifierRequestID
        )
        context.coordinator.renderSnapshot(snapshotText, paneTarget: paneTarget, isConnected: isConnected)
    }

    private func configure(_ terminalView: TerminalView) {
        terminalView.backgroundColor = UIColor(red: 0.025, green: 0.027, blue: 0.032, alpha: 1)
        terminalView.nativeBackgroundColor = UIColor(red: 0.025, green: 0.027, blue: 0.032, alpha: 1)
        terminalView.nativeForegroundColor = UIColor(red: 0.88, green: 0.91, blue: 0.93, alpha: 1)
        terminalView.caretColor = UIColor(red: 0.72, green: 0.92, blue: 0.56, alpha: 1)
        terminalView.keyboardAppearance = .dark
        terminalView.autocapitalizationType = .none
        terminalView.autocorrectionType = .no
        terminalView.spellCheckingType = .no
        terminalView.smartQuotesType = .no
        terminalView.smartDashesType = .no
        terminalView.allowMouseReporting = false
        terminalView.showsHorizontalScrollIndicator = false
        terminalView.alwaysBounceHorizontal = false
        terminalView.isDirectionalLockEnabled = true
        terminalView.contentInsetAdjustmentBehavior = .never
        terminalView.indicatorStyle = .white
        terminalView.keyboardDismissMode = .interactive
    }
}

extension SwiftTermTerminalView {
    final class Coordinator: NSObject, TerminalViewDelegate {
        var onSendData: (Data) -> Void
        var onResize: (Int, Int) -> Void

        private weak var terminalView: TerminalView?
        private var lastPaneTarget: String?
        private var lastSnapshot = ""
        private var lastSize: (cols: Int, rows: Int)?
        private var lastFocusRequestID = 0
        private var lastCopyRequestID = 0
        private var lastPasteRequestID = 0
        private var lastControlModifierRequestID = 0
        private var lastMetaModifierRequestID = 0

        init(
            onSendData: @escaping (Data) -> Void,
            onResize: @escaping (Int, Int) -> Void
        ) {
            self.onSendData = onSendData
            self.onResize = onResize
        }

        func attach(_ terminalView: TerminalView) {
            self.terminalView = terminalView
            terminalView.terminalDelegate = self
        }

        func applyCommands(
            to terminalView: TerminalView,
            focusRequestID: Int,
            copyRequestID: Int,
            pasteRequestID: Int,
            controlModifierRequestID: Int,
            metaModifierRequestID: Int
        ) {
            if focusRequestID != lastFocusRequestID {
                lastFocusRequestID = focusRequestID
                focus(terminalView)
            }
            if copyRequestID != lastCopyRequestID {
                lastCopyRequestID = copyRequestID
                focus(terminalView)
                terminalView.copy(nil)
            }
            if pasteRequestID != lastPasteRequestID {
                lastPasteRequestID = pasteRequestID
                focus(terminalView)
                terminalView.paste(nil)
            }
            if controlModifierRequestID != lastControlModifierRequestID {
                lastControlModifierRequestID = controlModifierRequestID
                terminalView.controlModifier = true
                focus(terminalView)
            }
            if metaModifierRequestID != lastMetaModifierRequestID {
                lastMetaModifierRequestID = metaModifierRequestID
                terminalView.metaModifier = true
                focus(terminalView)
            }
        }

        func renderSnapshot(_ snapshot: String, paneTarget: String?, isConnected: Bool) {
            guard let terminalView else { return }
            let normalizedPane = paneTarget?.trimmingCharacters(in: .whitespacesAndNewlines)
            let paneChanged = normalizedPane != lastPaneTarget

            if paneChanged {
                terminalView.getTerminal().resetToInitialState()
                terminalView.setContentOffset(.zero, animated: false)
                lastSnapshot = ""
                lastPaneTarget = normalizedPane
            }

            guard snapshot != lastSnapshot else { return }

            if paneChanged || !snapshot.hasPrefix(lastSnapshot) || !isConnected {
                terminalView.getTerminal().resetToInitialState()
                terminalView.setContentOffset(.zero, animated: false)
                terminalView.feed(text: terminalFeedText(from: snapshot))
            } else {
                let suffix = String(snapshot.dropFirst(lastSnapshot.count))
                terminalView.feed(text: terminalFeedText(from: suffix))
            }

            lastSnapshot = snapshot
        }

        private func focus(_ terminalView: TerminalView) {
            DispatchQueue.main.async {
                _ = terminalView.becomeFirstResponder()
            }
        }

        private func terminalFeedText(from snapshot: String) -> String {
            snapshot
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
                .replacingOccurrences(of: "\n", with: "\r\n")
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            onSendData(Data(data))
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 0, newRows > 0 else { return }
            if let lastSize, lastSize.cols == newCols, lastSize.rows == newRows {
                return
            }
            lastSize = (newCols, newRows)
            onResize(newCols, newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {}

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

        func scrolled(source: TerminalView, position: Double) {}

        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
            guard let url = URL(string: link) else { return }
            UIApplication.shared.open(url)
        }

        func bell(source: TerminalView) {
            HapticFeedback.shared.triggerImpactFeedback(style: .light)
        }

        func clipboardCopy(source: TerminalView, content: Data) {
            UIPasteboard.general.string = String(data: content, encoding: .utf8)
        }

        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}

private final class MMSMobileTerminalView: TerminalView {
    override var keyCommands: [UIKeyCommand]? {
        let commands = super.keyCommands ?? []
        return commands + [
            UIKeyCommand(title: "Copy", action: #selector(copy(_:)), input: "c", modifierFlags: .command),
            UIKeyCommand(title: "Paste", action: #selector(paste(_:)), input: "v", modifierFlags: .command),
            UIKeyCommand(title: "Select All", action: #selector(selectAll(_:)), input: "a", modifierFlags: .command),
        ]
    }
}
