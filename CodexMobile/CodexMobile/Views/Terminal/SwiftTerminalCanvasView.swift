// FILE: SwiftTerminalCanvasView.swift
// Purpose: SwiftTerm byte-stream renderer used only by the experimental Swift tab.
// Layer: View
// Exports: SwiftTerminalCanvasView
// Depends on: SwiftUI, UIKit, SwiftTerm, TerminalModels, AppFont

import CryptoKit
import Foundation
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
            usesDarkTheme: usesDarkTheme,
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
        context.coordinator.usesDarkTheme = usesDarkTheme
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
            streamView.configureGhostSafeRenderer()
            streamView.refreshGhostSafeCursorOverlay()
        }
    }
}

extension SwiftTerminalCanvasView {
    final class Coordinator: NSObject, TerminalViewDelegate {
        var usesDarkTheme: Bool
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
        private var escapeFilterState = TerminalEscapeFilterState.none
        private var contrastParserState = TerminalContrastParserState.none
        private var contrastDarkBackgroundActive = false
        private var contrastForegroundState = TerminalContrastForegroundState.defaultColor
        private var contrastForcedReadableForegroundActive = false
#if DEBUG
        private var lastOutputTraceKey = ""
        private var lastInputTraceKey = ""
#endif
        private var lastSentData = Data()
        private var lastSentAt: TimeInterval = 0
        private var pendingKeyboardPaste: KeyboardPasteBatch?

        init(
            usesDarkTheme: Bool,
            onSendData: @escaping (Data) -> Void,
            onResize: @escaping (Int, Int) -> Void,
            onTitle: @escaping (String) -> Void,
            onStatus: @escaping (String) -> Void
        ) {
            self.usesDarkTheme = usesDarkTheme
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
#if DEBUG
                lastOutputTraceKey = ""
                lastInputTraceKey = ""
                SwiftTerminalGhostTrace.event("ios.canvas.stream", fields: [
                    "stream": SwiftTerminalGhostTrace.redacted(streamId),
                    "pane": SwiftTerminalGhostTrace.redacted(normalizedPane),
                    "action": "reset"
                ])
#endif
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
#if DEBUG
                        let normalizedData = Data(bytes)
                        let traceKey = "\(data.count):\(SwiftTerminalGhostTrace.fingerprint(data))"
                        SwiftTerminalGhostTrace.bytes("ios.canvas.feed.raw", data: data, fields: [
                            "stream": SwiftTerminalGhostTrace.redacted(message.streamId),
                            "pane": SwiftTerminalGhostTrace.redacted(message.paneId),
                            "seq": "\(message.seq)",
                            "declared": "\(message.byteLength ?? -1)",
                            "repeat": traceKey == lastOutputTraceKey ? "immediate" : "no"
                        ])
                        SwiftTerminalGhostTrace.bytes("ios.canvas.feed.normalized", data: normalizedData, fields: [
                            "stream": SwiftTerminalGhostTrace.redacted(message.streamId),
                            "seq": "\(message.seq)"
                        ])
                        lastOutputTraceKey = traceKey
#endif
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
            escapeFilterState = .none
            contrastParserState = .none
            contrastDarkBackgroundActive = false
            contrastForegroundState = .defaultColor
            contrastForcedReadableForegroundActive = false
            terminalView.getTerminal().resetToInitialState()
            terminalView.setContentOffset(.zero, animated: false)
        }

        private func normalizedOutputBytes(from data: Data) -> [UInt8] {
            var filtered: [UInt8] = []
            filtered.reserveCapacity(data.count + min(data.count, 128))

            for byte in data {
                filterTerminalEscapeByte(byte, into: &filtered)
            }

            guard !usesDarkTheme else { return filtered }
            return lightTerminalContrastAdjustedBytes(from: filtered)
        }

        private func lightTerminalContrastAdjustedBytes(from bytes: [UInt8]) -> [UInt8] {
            var output: [UInt8] = []
            output.reserveCapacity(bytes.count + min(bytes.count, 64))
            for byte in bytes {
                filterLightTerminalContrastByte(byte, into: &output)
            }
            return output
        }

        private func filterLightTerminalContrastByte(_ byte: UInt8, into output: inout [UInt8]) {
            switch contrastParserState {
            case .none:
                if byte == TerminalByte.escape {
                    contrastParserState = .escape([byte])
                } else {
                    output.append(byte)
                }
            case .escape(var buffer):
                buffer.append(byte)
                if byte == TerminalByte.csiMarker {
                    contrastParserState = .csi(buffer)
                } else {
                    output.append(contentsOf: buffer)
                    contrastParserState = .none
                }
            case .csi(var buffer):
                buffer.append(byte)
                if TerminalByte.isCSIFinalByte(byte) {
                    output.append(contentsOf: buffer)
                    if byte == TerminalByte.sgrFinal {
                        applySGRContrastState(from: buffer)
                        if contrastForcedReadableForegroundActive && !contrastDarkBackgroundActive {
                            output.append(contentsOf: TerminalByte.defaultForegroundSequence)
                            contrastForegroundState = .defaultColor
                            contrastForcedReadableForegroundActive = false
                        }
                        if shouldForceReadableForegroundOnDarkBackground {
                            output.append(contentsOf: TerminalByte.brightWhiteForegroundSequence)
                            contrastForegroundState = .light
                            contrastForcedReadableForegroundActive = true
                        }
                    }
                    contrastParserState = .none
                } else if buffer.count > 128 {
                    output.append(contentsOf: buffer)
                    contrastParserState = .none
                } else {
                    contrastParserState = .csi(buffer)
                }
            }
        }

        private var shouldForceReadableForegroundOnDarkBackground: Bool {
            contrastDarkBackgroundActive
                && (contrastForegroundState == .defaultColor || contrastForegroundState == .dark)
        }

        private func applySGRContrastState(from sequence: [UInt8]) {
            guard sequence.count >= 3 else { return }
            let parameterBytes = sequence.dropFirst(2).dropLast()
            let parameterText = String(bytes: parameterBytes, encoding: .ascii) ?? ""
            let normalizedText = parameterText.replacingOccurrences(of: ":", with: ";")
            let parameters = normalizedText.split(separator: ";", omittingEmptySubsequences: false)
                .map { Int($0) ?? 0 }
            applySGRContrastParameters(parameters.isEmpty ? [0] : parameters)
        }

        private func applySGRContrastParameters(_ parameters: [Int]) {
            var index = 0
            while index < parameters.count {
                let value = parameters[index]
                switch value {
                case 0:
                    contrastDarkBackgroundActive = false
                    contrastForegroundState = .defaultColor
                    contrastForcedReadableForegroundActive = false
                case 1, 2, 3, 4, 5, 9, 22, 23, 24, 25, 29:
                    break
                case 30, 90:
                    contrastForegroundState = .dark
                    contrastForcedReadableForegroundActive = false
                case 31...36, 91...96:
                    contrastForegroundState = .other
                    contrastForcedReadableForegroundActive = false
                case 37, 97:
                    contrastForegroundState = .light
                    contrastForcedReadableForegroundActive = false
                case 39:
                    contrastForegroundState = .defaultColor
                    contrastForcedReadableForegroundActive = false
                case 40, 100:
                    contrastDarkBackgroundActive = true
                case 41...47, 101...107:
                    contrastDarkBackgroundActive = false
                case 49:
                    contrastDarkBackgroundActive = false
                case 38:
                    let result = readExtendedColorState(parameters, start: index)
                    if let foregroundState = result.foregroundState {
                        contrastForegroundState = foregroundState
                        contrastForcedReadableForegroundActive = false
                    }
                    index = result.nextIndex
                case 48:
                    let result = readExtendedColorState(parameters, start: index)
                    if let isDarkBackground = result.isDarkBackground {
                        contrastDarkBackgroundActive = isDarkBackground
                    }
                    index = result.nextIndex
                default:
                    break
                }
                index += 1
            }
        }

        private func readExtendedColorState(
            _ parameters: [Int],
            start: Int
        ) -> (foregroundState: TerminalContrastForegroundState?, isDarkBackground: Bool?, nextIndex: Int) {
            guard start + 1 < parameters.count else {
                return (nil, nil, start)
            }
            let mode = parameters[start + 1]
            if mode == 5, start + 2 < parameters.count {
                let colorIndex = parameters[start + 2]
                let isDark = isDarkANSIColorIndex(colorIndex)
                return (isDark ? .dark : .other, isDark, start + 2)
            }
            if mode == 2, start + 4 < parameters.count {
                let red = parameters[start + 2]
                let green = parameters[start + 3]
                let blue = parameters[start + 4]
                let isDark = isDarkTrueColor(red: red, green: green, blue: blue)
                return (isDark ? .dark : .other, isDark, start + 4)
            }
            return (nil, nil, start + 1)
        }

        private func isDarkANSIColorIndex(_ index: Int) -> Bool {
            index == 0 || index == 8 || (232...237).contains(index)
        }

        private func isDarkTrueColor(red: Int, green: Int, blue: Int) -> Bool {
            let r = max(0, min(255, red))
            let g = max(0, min(255, green))
            let b = max(0, min(255, blue))
            let luminance = (0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)) / 255.0
            return luminance < 0.24
        }

        private func filterTerminalEscapeByte(_ byte: UInt8, into output: inout [UInt8]) {
            switch escapeFilterState {
            case .none:
                if byte == TerminalByte.escape {
                    escapeFilterState = .sawEscape
                } else {
                    appendNormalizedOutputByte(byte, into: &output)
                }
            case .sawEscape:
                if byte == TerminalByte.screenTitleMarker {
                    escapeFilterState = .inScreenTitle
                } else {
                    appendNormalizedOutputByte(TerminalByte.escape, into: &output)
                    escapeFilterState = .none
                    filterTerminalEscapeByte(byte, into: &output)
                }
            case .inScreenTitle:
                if byte == TerminalByte.bell {
                    escapeFilterState = .none
                } else if byte == TerminalByte.escape {
                    escapeFilterState = .inScreenTitleSawEscape
                }
            case .inScreenTitleSawEscape:
                if byte == TerminalByte.stringTerminator {
                    escapeFilterState = .none
                } else if byte != TerminalByte.escape {
                    escapeFilterState = .inScreenTitle
                }
            }
        }

        private func appendNormalizedOutputByte(_ byte: UInt8, into output: inout [UInt8]) {
            if byte == TerminalByte.lineFeed {
                if !lastOutputByteWasCR {
                    output.append(TerminalByte.carriageReturn)
                }
                output.append(byte)
                lastOutputByteWasCR = false
            } else {
                output.append(byte)
                lastOutputByteWasCR = byte == TerminalByte.carriageReturn
            }
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
                _ = terminalView.becomeFirstResponder()
            }
        }

        private func blur(_ terminalView: TerminalView) {
            DispatchQueue.main.async {
                _ = terminalView.resignFirstResponder()
            }
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            let payload = Data(data)
            if bufferKeyboardPasteIfNeeded(payload) {
                return
            }
            flushPendingKeyboardPaste()
            guard !shouldSuppressDuplicateSend(payload) else { return }
#if DEBUG
            let traceKey = "\(payload.count):\(SwiftTerminalGhostTrace.fingerprint(payload))"
            SwiftTerminalGhostTrace.bytes("ios.canvas.input", data: payload, fields: [
                "stream": SwiftTerminalGhostTrace.redacted(lastStreamId),
                "repeat": traceKey == lastInputTraceKey ? "immediate" : "no"
            ])
            lastInputTraceKey = traceKey
#endif
            (source as? MMSStreamTerminalView)?.forceGhostSafeRendererRefresh()
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


private enum TerminalEscapeFilterState {
    case none
    case sawEscape
    case inScreenTitle
    case inScreenTitleSawEscape
}

private enum TerminalContrastParserState {
    case none
    case escape([UInt8])
    case csi([UInt8])
}

private enum TerminalContrastForegroundState {
    case defaultColor
    case dark
    case light
    case other
}

private enum TerminalByte {
    static let bell: UInt8 = 0x07
    static let escape: UInt8 = 0x1B
    static let lineFeed: UInt8 = 0x0A
    static let carriageReturn: UInt8 = 0x0D
    static let csiMarker: UInt8 = 0x5B
    static let sgrFinal: UInt8 = 0x6D
    static let screenTitleMarker: UInt8 = 0x6B
    static let stringTerminator: UInt8 = 0x5C
    static let brightWhiteForegroundSequence: [UInt8] = [0x1B, 0x5B, 0x39, 0x37, 0x6D]
    static let defaultForegroundSequence: [UInt8] = [0x1B, 0x5B, 0x33, 0x39, 0x6D]

    static func isCSIFinalByte(_ byte: UInt8) -> Bool {
        (0x40...0x7E).contains(byte)
    }
}

private final class MMSStreamTerminalView: TerminalView {
    private var preservedScrollY: CGFloat?
    private var preserveScrollUntil: TimeInterval = 0
    private var isApplyingStreamFeed = false
    private weak var suppressedCaretView: UIView?
    private let ghostSafeCursorOverlay = UIView(frame: .zero)
    private var hasInstalledGhostSafeCursorOverlay = false
    private var isGhostSafeCursorVisible = true
    private var hasPendingGhostSafeCursorRefresh = false

    func applyTerminalFontIfNeeded(_ newFont: UIFont) {
        guard fontSignature(for: font) != fontSignature(for: newFont) else { return }
        font = newFont
        scheduleGhostSafeCursorOverlayRefresh()
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

    func configureGhostSafeRenderer() {
        isOpaque = true
        layer.isOpaque = true
        clipsToBounds = true
        layer.masksToBounds = true
        contentMode = .redraw
        clearsContextBeforeDrawing = true
    }

    override func cursorStyleChanged(source: Terminal, newStyle: CursorStyle) {
        super.cursorStyleChanged(source: source, newStyle: .steadyBar)
        refreshGhostSafeCursorOverlay()
        guard newStyle != .steadyBar else { return }
        DispatchQueue.main.async { [weak source] in
            source?.setCursorStyle(.steadyBar)
        }
    }

    override func showCursor(source: Terminal) {
        isGhostSafeCursorVisible = true
        refreshGhostSafeCursorOverlay()
    }

    override func hideCursor(source: Terminal) {
        isGhostSafeCursorVisible = false
        suppressedCaretView?.removeFromSuperview()
        ghostSafeCursorOverlay.isHidden = true
    }

    override func addSubview(_ view: UIView) {
        guard isSwiftTermCaretView(view) else {
            super.addSubview(view)
            return
        }
        suppressedCaretView = view
        view.isHidden = true
        view.removeFromSuperview()
        scheduleGhostSafeCursorOverlayRefresh()
    }

    func refreshGhostSafeCursorOverlay() {
        hasPendingGhostSafeCursorRefresh = false
        suppressedCaretView?.removeFromSuperview()
        installGhostSafeCursorOverlayIfNeeded()

        let frame = caretFrame
        guard isGhostSafeCursorVisible, frame.width > 0, frame.height > 0 else {
            ghostSafeCursorOverlay.isHidden = true
            return
        }

        let scale = max(window?.screen.scale ?? UIScreen.main.scale, 1)
        let width = max(2, 2 / scale)
        ghostSafeCursorOverlay.frame = CGRect(
            x: frame.minX,
            y: frame.minY,
            width: min(width, frame.width),
            height: frame.height
        )
        ghostSafeCursorOverlay.backgroundColor = caretColor
        ghostSafeCursorOverlay.layer.removeAllAnimations()
        ghostSafeCursorOverlay.layer.opacity = 1
        ghostSafeCursorOverlay.isHidden = false
        bringSubviewToFront(ghostSafeCursorOverlay)
    }

    func forceGhostSafeRendererRefresh() {
        refreshGhostSafeCursorOverlay()
        setNeedsDisplay(bounds)
        layer.setNeedsDisplay()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.suppressedCaretView?.removeFromSuperview()
            self.setNeedsDisplay(self.bounds)
            self.layer.setNeedsDisplay()
            self.refreshGhostSafeCursorOverlay()
        }
    }

    private func scheduleGhostSafeCursorOverlayRefresh() {
        guard !hasPendingGhostSafeCursorRefresh else { return }
        hasPendingGhostSafeCursorRefresh = true
        DispatchQueue.main.async { [weak self] in
            self?.refreshGhostSafeCursorOverlay()
        }
    }

    private func installGhostSafeCursorOverlayIfNeeded() {
        guard !hasInstalledGhostSafeCursorOverlay || ghostSafeCursorOverlay.superview !== self else { return }
        ghostSafeCursorOverlay.isUserInteractionEnabled = false
        ghostSafeCursorOverlay.layer.masksToBounds = true
        super.addSubview(ghostSafeCursorOverlay)
        hasInstalledGhostSafeCursorOverlay = true
    }

    private func isSwiftTermCaretView(_ view: UIView) -> Bool {
        guard view !== ghostSafeCursorOverlay else { return false }
        let describedName = String(describing: type(of: view))
        let reflectedName = String(reflecting: type(of: view))
        return describedName.contains("CaretView") || reflectedName.contains("CaretView")
    }

    func feedPreservingScroll(_ operation: () -> Void) {
        layoutIfNeeded()
        let previousY = clampedVerticalOffset(contentOffset.y)
        let shouldRestore = maxVerticalOffset > 0 && !isNearBottom()

        isApplyingStreamFeed = true
        operation()
        isApplyingStreamFeed = false
        forceGhostSafeRendererRefresh()
        refreshGhostSafeCursorOverlay()

        guard shouldRestore else { return }
        layoutIfNeeded()
        let restoredY = clampedVerticalOffset(previousY)
        preservedScrollY = restoredY
        preserveScrollUntil = ProcessInfo.processInfo.systemUptime + 2.0
        super.setContentOffset(CGPoint(x: 0, y: restoredY), animated: false)
        forceGhostSafeRendererRefresh()
        refreshGhostSafeCursorOverlay()
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
        refreshGhostSafeCursorOverlay()
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

#if DEBUG
private enum SwiftTerminalGhostTrace {
    static func bytes(_ label: String, data: Data, fields: [String: String] = [:]) {
        var parts = ["[MMSGhostTrace] \(label)"]
        append(fields, to: &parts)
        parts.append("len=\(data.count)")
        parts.append("sha=\(fingerprint(data))")
        parts.append("head=\(hex(data.prefix(8)))")
        parts.append("tail=\(hex(data.suffix(8)))")
        print(parts.joined(separator: " "))
    }

    static func event(_ label: String, fields: [String: String] = [:]) {
        var parts = ["[MMSGhostTrace] \(label)"]
        append(fields, to: &parts)
        print(parts.joined(separator: " "))
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
    }

    static func redacted(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return fingerprint(Data(value.utf8)).prefix(10).description
    }

    private static func append(_ fields: [String: String], to parts: inout [String]) {
        for key in fields.keys.sorted() {
            guard let value = fields[key], !value.isEmpty else { continue }
            parts.append("\(key)=\(value)")
        }
    }

    private static func hex(_ bytes: Data.SubSequence) -> String {
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        return value.isEmpty ? "-" : value
    }
}
#endif
