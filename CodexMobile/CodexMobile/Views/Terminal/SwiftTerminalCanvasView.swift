// FILE: SwiftTerminalCanvasView.swift
// Purpose: SwiftTerm byte-stream renderer used only by the experimental Swift tab.
// Layer: View
// Exports: SwiftTerminalCanvasView
// Depends on: SwiftUI, UIKit, SwiftTerm, TerminalModels, AppFont

import SwiftTerm
import SwiftUI
import UIKit

struct SwiftTerminalCanvasView: UIViewRepresentable {
    let paneTarget: String?
    let streamId: String?
    let messages: [TerminalStreamMessage]
    let fontSize: CGFloat
    let usesDarkTheme: Bool
    let focusRequestID: Int
    let copyRequestID: Int
    let pasteRequestID: Int
    let controlModifierRequestID: Int
    let metaModifierRequestID: Int
    let resetRequestID: Int
    let pageUpRequestID: Int
    let pageDownRequestID: Int
    let blurRequestID: Int
    let onSendData: (Data) -> Void
    let onResize: (Int, Int) -> Void
    let onTitle: (String) -> Void
    let onStatus: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onSendData: onSendData,
            onResize: onResize,
            onTitle: onTitle,
            onStatus: onStatus
        )
    }

    func makeUIView(context: Context) -> TerminalView {
        let terminalView = MMSStreamTerminalView(
            frame: .zero,
            font: AppFont.terminalMonoUIFont(size: fontSize, textStyle: .caption1)
        )
        terminalView.terminalDelegate = context.coordinator
        context.coordinator.attach(terminalView)
        configure(terminalView)
        terminalView.getTerminal().changeHistorySize(5_000)
        return terminalView
    }

    func updateUIView(_ terminalView: TerminalView, context: Context) {
        context.coordinator.onSendData = onSendData
        context.coordinator.onResize = onResize
        context.coordinator.onTitle = onTitle
        context.coordinator.onStatus = onStatus
        configure(terminalView)
        let nextFont = AppFont.terminalMonoUIFont(size: fontSize, textStyle: .caption1)
        if let streamView = terminalView as? MMSStreamTerminalView {
            streamView.applyTerminalFontIfNeeded(nextFont)
        } else {
            terminalView.font = nextFont
        }
        context.coordinator.applyCommands(
            to: terminalView,
            paneTarget: paneTarget,
            streamId: streamId,
            messages: messages,
            focusRequestID: focusRequestID,
            copyRequestID: copyRequestID,
            pasteRequestID: pasteRequestID,
            controlModifierRequestID: controlModifierRequestID,
            metaModifierRequestID: metaModifierRequestID,
            resetRequestID: resetRequestID,
            pageUpRequestID: pageUpRequestID,
            pageDownRequestID: pageDownRequestID,
            blurRequestID: blurRequestID
        )
    }

    private func configure(_ terminalView: TerminalView) {
        let backgroundColor = usesDarkTheme
            ? UIColor(red: 0.02, green: 0.024, blue: 0.029, alpha: 1)
            : UIColor.systemBackground
        terminalView.backgroundColor = backgroundColor
        terminalView.nativeBackgroundColor = backgroundColor
        terminalView.nativeForegroundColor = usesDarkTheme
            ? UIColor(red: 0.86, green: 0.90, blue: 0.92, alpha: 1)
            : UIColor.label
        terminalView.caretColor = usesDarkTheme
            ? UIColor(red: 0.63, green: 0.92, blue: 0.52, alpha: 1)
            : UIColor(red: 0.21, green: 0.58, blue: 0.38, alpha: 1)
        terminalView.keyboardAppearance = usesDarkTheme ? .dark : .default
        terminalView.autocapitalizationType = .none
        terminalView.autocorrectionType = .no
        terminalView.spellCheckingType = .no
        terminalView.smartQuotesType = .no
        terminalView.smartDashesType = .no
        terminalView.allowMouseReporting = false
        terminalView.bounces = true
        terminalView.alwaysBounceVertical = true
        terminalView.showsHorizontalScrollIndicator = false
        terminalView.alwaysBounceHorizontal = false
        terminalView.isDirectionalLockEnabled = true
        terminalView.contentInsetAdjustmentBehavior = .never
        terminalView.contentInset = .zero
        terminalView.scrollIndicatorInsets = .zero
        terminalView.indicatorStyle = usesDarkTheme ? .white : .black
        terminalView.keyboardDismissMode = .onDrag
        if let streamView = terminalView as? MMSStreamTerminalView {
            streamView.disableSwiftTermAccessory()
            streamView.enforceGhostSafeCursorStyle()
        }
    }
}

extension SwiftTerminalCanvasView {
    final class Coordinator: NSObject, TerminalViewDelegate {
        var onSendData: (Data) -> Void
        var onResize: (Int, Int) -> Void
        var onTitle: (String) -> Void
        var onStatus: (String) -> Void

        private weak var terminalView: TerminalView?
        private var lastPaneTarget: String?
        private var lastStreamId: String?
        private var lastSeq = 0
        private var lastSize: (cols: Int, rows: Int)?
        private var lastFocusRequestID = 0
        private var lastCopyRequestID = 0
        private var lastPasteRequestID = 0
        private var lastControlModifierRequestID = 0
        private var lastMetaModifierRequestID = 0
        private var lastResetRequestID = 0
        private var lastPageUpRequestID = 0
        private var lastPageDownRequestID = 0
        private var lastBlurRequestID = 0
        private var lastOutputByteWasCR = false
        private var lastSentData = Data()
        private var lastSentAt: TimeInterval = 0
        private var pendingKeyboardPaste: KeyboardPasteBatch?

        init(
            onSendData: @escaping (Data) -> Void,
            onResize: @escaping (Int, Int) -> Void,
            onTitle: @escaping (String) -> Void,
            onStatus: @escaping (String) -> Void
        ) {
            self.onSendData = onSendData
            self.onResize = onResize
            self.onTitle = onTitle
            self.onStatus = onStatus
        }

        func attach(_ terminalView: TerminalView) {
            self.terminalView = terminalView
        }

        func applyCommands(
            to terminalView: TerminalView,
            paneTarget: String?,
            streamId: String?,
            messages: [TerminalStreamMessage],
            focusRequestID: Int,
            copyRequestID: Int,
            pasteRequestID: Int,
            controlModifierRequestID: Int,
            metaModifierRequestID: Int,
            resetRequestID: Int,
            pageUpRequestID: Int,
            pageDownRequestID: Int,
            blurRequestID: Int
        ) {
            let normalizedPane = paneTarget?.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedPane != lastPaneTarget || streamId != lastStreamId {
                reset(terminalView)
                lastPaneTarget = normalizedPane
                lastStreamId = streamId
                lastSeq = 0
            }

            if resetRequestID != lastResetRequestID {
                lastResetRequestID = resetRequestID
                reset(terminalView)
                lastSeq = 0
            }

            if focusRequestID != lastFocusRequestID {
                lastFocusRequestID = focusRequestID
                focus(terminalView)
            }
            if copyRequestID != lastCopyRequestID {
                lastCopyRequestID = copyRequestID
                terminalView.copy(nil)
            }
            if pasteRequestID != lastPasteRequestID {
                lastPasteRequestID = pasteRequestID
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
            if pageUpRequestID != lastPageUpRequestID {
                lastPageUpRequestID = pageUpRequestID
                terminalView.pageUp()
            }
            if pageDownRequestID != lastPageDownRequestID {
                lastPageDownRequestID = pageDownRequestID
                terminalView.pageDown()
            }
            if blurRequestID != lastBlurRequestID {
                lastBlurRequestID = blurRequestID
                blur(terminalView)
            }

            guard isReadyToFeed(terminalView) else {
                onStatus("sizing")
                return
            }
            feed(messages: messages, into: terminalView)
        }

        private func feed(messages: [TerminalStreamMessage], into terminalView: TerminalView) {
            let orderedMessages = messages
                .filter { $0.seq > lastSeq }
                .sorted { $0.seq < $1.seq }
            guard !orderedMessages.isEmpty else { return }

            for message in orderedMessages {
                switch message.type {
                case .ready:
                    onStatus("ready")
                case .replayStart:
                    if message.reset == true {
                        reset(terminalView)
                    }
                    onStatus("replay")
                case .output:
                    if let base64 = message.base64,
                       let data = Data(base64Encoded: base64) {
                        let bytes = normalizedOutputBytes(from: data)
                        if let streamView = terminalView as? MMSStreamTerminalView {
                            streamView.feedPreservingScroll {
                                terminalView.feed(byteArray: bytes[...])
                            }
                        } else {
                            terminalView.feed(byteArray: bytes[...])
                        }
                        clampHorizontalOffset(terminalView)
                    }
                case .title:
                    if let title = message.title, !title.isEmpty {
                        onTitle(title)
                    }
                case .cwd:
                    if let cwd = message.cwd, !cwd.isEmpty {
                        onStatus(cwd)
                    }
                case .bell:
                    HapticFeedback.shared.triggerImpactFeedback(style: .light)
                case .error:
                    onStatus(message.message ?? "stream error")
                case .exit:
                    onStatus(message.reason ?? "stream exited")
                case .heartbeat:
                    break
                case .inputAck, .resizeAck, .replayEnd:
                    break
                }
                lastSeq = max(lastSeq, message.seq)
            }
        }

        private func reset(_ terminalView: TerminalView) {
            flushPendingKeyboardPaste()
            lastOutputByteWasCR = false
            terminalView.getTerminal().resetToInitialState()
            terminalView.setContentOffset(.zero, animated: false)
        }

        private func normalizedOutputBytes(from data: Data) -> [UInt8] {
            var output: [UInt8] = []
            output.reserveCapacity(data.count + min(data.count, 128))

            for byte in data {
                if byte == 0x0A {
                    if !lastOutputByteWasCR {
                        output.append(0x0D)
                    }
                    output.append(byte)
                    lastOutputByteWasCR = false
                } else {
                    output.append(byte)
                    lastOutputByteWasCR = byte == 0x0D
                }
            }

            return output
        }

        private func isReadyToFeed(_ terminalView: TerminalView) -> Bool {
            let size = terminalView.getTerminal().getDims()
            return terminalView.bounds.width > 0
                && terminalView.bounds.height > 0
                && size.cols > 10
                && size.rows > 5
        }

        private func clampHorizontalOffset(_ terminalView: TerminalView) {
            guard terminalView.contentOffset.x != 0 else { return }
            terminalView.setContentOffset(CGPoint(x: 0, y: terminalView.contentOffset.y), animated: false)
        }

        private func focus(_ terminalView: TerminalView) {
            DispatchQueue.main.async {
                if let streamView = terminalView as? MMSStreamTerminalView {
                    streamView.enableKeyboardFocus()
                }
                _ = terminalView.becomeFirstResponder()
            }
        }

        private func blur(_ terminalView: TerminalView) {
            DispatchQueue.main.async {
                if let streamView = terminalView as? MMSStreamTerminalView {
                    streamView.suppressKeyboardFocus()
                } else {
                    _ = terminalView.resignFirstResponder()
                    terminalView.window?.endEditing(true)
                }
                DispatchQueue.main.async {
                    if let streamView = terminalView as? MMSStreamTerminalView {
                        streamView.suppressKeyboardFocus()
                    } else {
                        _ = terminalView.resignFirstResponder()
                        terminalView.window?.endEditing(true)
                    }
                }
            }
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let payload = Data(data)
            if bufferKeyboardPasteIfNeeded(payload) {
                return
            }
            flushPendingKeyboardPaste()
            guard !shouldSuppressDuplicateSend(payload) else { return }
            onSendData(payload)
        }

        private func bufferKeyboardPasteIfNeeded(_ data: Data) -> Bool {
            guard let text = String(data: data, encoding: .utf8),
                  let clipboard = UIPasteboard.general.string,
                  isKeyboardClipboardPasteCandidate(text: text, clipboard: clipboard) else {
                return false
            }

            let now = ProcessInfo.processInfo.systemUptime
            if pendingKeyboardPaste?.clipboard != clipboard {
                flushPendingKeyboardPaste()
                pendingKeyboardPaste = KeyboardPasteBatch(clipboard: clipboard, startedAt: now)
            }
            pendingKeyboardPaste?.append(text)
            schedulePendingKeyboardPasteFlush()
            return true
        }

        private func schedulePendingKeyboardPasteFlush() {
            pendingKeyboardPaste?.flushWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                self?.flushPendingKeyboardPaste()
            }
            pendingKeyboardPaste?.flushWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
        }

        private func flushPendingKeyboardPaste() {
            guard let batch = pendingKeyboardPaste else { return }
            batch.flushWorkItem?.cancel()
            pendingKeyboardPaste = nil

            let payloadText = batch.shouldUseClipboard ? batch.clipboard : batch.joinedChunks
            guard !payloadText.isEmpty else { return }
            let payload = Data(payloadText.utf8)
            guard !shouldSuppressDuplicateSend(payload) else { return }
            onSendData(payload)
        }

        private func isKeyboardClipboardPasteCandidate(text: String, clipboard: String) -> Bool {
            let continuingBatch = pendingKeyboardPaste?.clipboard == clipboard
            guard clipboard.count >= 12,
                  clipboard.contains(" "),
                  !clipboard.contains("\n"),
                  !clipboard.contains("\r"),
                  (continuingBatch || text.count > 1),
                  text.unicodeScalars.allSatisfy({ scalar in
                      scalar.value >= 0x20 && scalar.value != 0x7F
                  }) else {
                return false
            }

            if continuingBatch && text == " " {
                return true
            }

            if text == clipboard || clipboard.hasPrefix(text) || clipboard.contains(text) {
                return true
            }

            let compactClipboard = clipboard.replacingOccurrences(of: " ", with: "")
            let compactText = text.replacingOccurrences(of: " ", with: "")
            return compactText.count > 1 && compactClipboard.contains(compactText)
        }

        private func shouldSuppressDuplicateSend(_ data: Data) -> Bool {
            let interval: TimeInterval
            if isLineEnding(data) {
                interval = 0.35
            } else if isPasteLikeText(data) {
                interval = 0.16
            } else {
                lastSentData = Data()
                lastSentAt = 0
                return false
            }
            let now = ProcessInfo.processInfo.systemUptime
            let fingerprint = inputFingerprint(for: data)
            defer {
                lastSentData = fingerprint
                lastSentAt = now
            }
            guard fingerprint == lastSentData, now - lastSentAt < interval else {
                return false
            }
            return true
        }

        private func isLineEnding(_ data: Data) -> Bool {
            data == Data([0x0A]) || data == Data([0x0D]) || data == Data([0x0D, 0x0A])
        }

        private func isPasteLikeText(_ data: Data) -> Bool {
            guard data.count > 1,
                  data.first != 0x1B,
                  !data.contains(where: { $0 < 0x20 || $0 == 0x7F }),
                  String(data: data, encoding: .utf8) != nil else {
                return false
            }
            return true
        }

        private func inputFingerprint(for data: Data) -> Data {
            if data == Data([0x0A]) || data == Data([0x0D]) || data == Data([0x0D, 0x0A]) {
                return Data([0x0D])
            }
            return data
        }

        private final class KeyboardPasteBatch {
            let clipboard: String
            let startedAt: TimeInterval
            var chunks: [String] = []
            var flushWorkItem: DispatchWorkItem?

            init(clipboard: String, startedAt: TimeInterval) {
                self.clipboard = clipboard
                self.startedAt = startedAt
            }

            var joinedChunks: String {
                chunks.joined()
            }

            var shouldUseClipboard: Bool {
                let joined = joinedChunks
                if joined == clipboard {
                    return true
                }
                guard chunks.count > 1 else {
                    return false
                }
                if clipboard.hasPrefix(joined) {
                    return false
                }
                let compactClipboard = clipboard.replacingOccurrences(of: " ", with: "")
                let compactJoined = joined.replacingOccurrences(of: " ", with: "")
                return !compactClipboard.hasPrefix(compactJoined)
            }

            func append(_ text: String) {
                chunks.append(text)
            }
        }

        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
            guard newCols > 0, newRows > 0 else { return }
            if let lastSize, lastSize.cols == newCols, lastSize.rows == newRows {
                return
            }
            lastSize = (newCols, newRows)
            onResize(newCols, newRows)
        }

        func setTerminalTitle(source: TerminalView, title: String) {
            onTitle(title)
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            if let directory, !directory.isEmpty {
                onStatus(directory)
            }
        }

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

private final class MMSStreamTerminalView: TerminalView {
    private var preservedScrollY: CGFloat?
    private var preserveScrollUntil: TimeInterval = 0
    private var isApplyingStreamFeed = false
    private var allowsKeyboardFocus = true

    override var canBecomeFirstResponder: Bool {
        allowsKeyboardFocus && super.canBecomeFirstResponder
    }

    func enableKeyboardFocus() {
        allowsKeyboardFocus = true
    }

    func suppressKeyboardFocus() {
        allowsKeyboardFocus = false
        _ = resignFirstResponder()
        window?.endEditing(true)
        superview?.endEditing(true)
    }

    func applyTerminalFontIfNeeded(_ newFont: UIFont) {
        guard fontSignature(for: font) != fontSignature(for: newFont) else { return }
        font = newFont
    }

    func disableSwiftTermAccessory() {
        inputAccessoryView = nil
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        if isFirstResponder {
            reloadInputViews()
        }
    }

    func enforceGhostSafeCursorStyle() {
        getTerminal().setCursorStyle(.steadyBar)
    }

    override func cursorStyleChanged(source: Terminal, newStyle: CursorStyle) {
        super.cursorStyleChanged(source: source, newStyle: .steadyBar)
        guard newStyle != .steadyBar else { return }
        DispatchQueue.main.async { [weak source] in
            source?.setCursorStyle(.steadyBar)
        }
    }

    func feedPreservingScroll(_ operation: () -> Void) {
        layoutIfNeeded()
        let previousY = clampedVerticalOffset(contentOffset.y)
        let shouldRestore = maxVerticalOffset > 0 && !isNearBottom()

        isApplyingStreamFeed = true
        operation()
        isApplyingStreamFeed = false

        guard shouldRestore else { return }
        layoutIfNeeded()
        let restoredY = clampedVerticalOffset(previousY)
        preservedScrollY = restoredY
        preserveScrollUntil = ProcessInfo.processInfo.systemUptime + 2.0
        super.setContentOffset(CGPoint(x: 0, y: restoredY), animated: false)
    }

    override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
        var y = clampedVerticalOffset(contentOffset.y)
        let maxY = maxVerticalOffset
        let now = ProcessInfo.processInfo.systemUptime

        if isTracking || isDragging || isDecelerating {
            preservedScrollY = y
            preserveScrollUntil = now + 1.5
        } else if !isApplyingStreamFeed, now < preserveScrollUntil, let preservedScrollY, abs(y - maxY) < 1 {
            // SwiftTerm snaps to bottom on feed; keep manual scroll stable briefly.
            y = clampedVerticalOffset(preservedScrollY)
        }

        super.setContentOffset(CGPoint(x: 0, y: y), animated: animated)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if contentOffset.x != 0 {
            setContentOffset(CGPoint(x: 0, y: contentOffset.y), animated: false)
        }
    }

    private var maxVerticalOffset: CGFloat {
        max(0, contentSize.height + adjustedContentInset.bottom + adjustedContentInset.top - bounds.height)
    }

    private func clampedVerticalOffset(_ y: CGFloat) -> CGFloat {
        min(max(y, -adjustedContentInset.top), maxVerticalOffset)
    }

    private func isNearBottom(threshold: CGFloat = 56) -> Bool {
        maxVerticalOffset - contentOffset.y < threshold
    }

    private func fontSignature(for font: UIFont) -> String {
        let traits = font.fontDescriptor.symbolicTraits.rawValue
        return "\(font.fontName)|\(font.pointSize)|\(traits)"
    }

    @objc override func paste(_ sender: Any?) {
        guard let text = UIPasteboard.general.string, !text.isEmpty else { return }
        if getTerminal().bracketedPasteMode {
            let start: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x30, 0x7E]
            send(data: start[...])
        }
        let bytes = Array(text.utf8)
        send(data: bytes[...])
        if getTerminal().bracketedPasteMode {
            let end: [UInt8] = [0x1B, 0x5B, 0x32, 0x30, 0x31, 0x7E]
            send(data: end[...])
        }
    }

    override var keyCommands: [UIKeyCommand]? {
        let commands = super.keyCommands ?? []
        return commands + [
            UIKeyCommand(title: "Copy", action: #selector(copy(_:)), input: "c", modifierFlags: .command),
            UIKeyCommand(title: "Paste", action: #selector(paste(_:)), input: "v", modifierFlags: .command),
            UIKeyCommand(title: "Select All", action: #selector(selectAll(_:)), input: "a", modifierFlags: .command),
        ]
    }
}
