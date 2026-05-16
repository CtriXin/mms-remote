// FILE: StableTerminalSnapshotTextView.swift
// Purpose: UIKit-backed selectable stable Terminal snapshot renderer.
// Layer: View support

import SwiftUI
import UIKit

struct StableTerminalSnapshotTextView: UIViewRepresentable {
    let attributedText: AttributedString
    let fontSize: CGFloat
    let backgroundColor: UIColor
    let scrollTopRequestID: Int
    let scrollBottomRequestID: Int
    let resetKey: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView(frame: .zero)
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.showsVerticalScrollIndicator = true
        textView.showsHorizontalScrollIndicator = false
        textView.keyboardDismissMode = .interactive
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byCharWrapping
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 14, bottom: 18, right: 14)
        configure(textView, context: context)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        configure(textView, context: context)
    }

    private func configure(_ textView: UITextView, context: Context) {
        let font = AppFont.terminalMonoUIFont(size: fontSize, textStyle: .caption1)
        let plainText = String(attributedText.characters)
        let didChangeResetKey = context.coordinator.lastResetKey != resetKey
        let didChangeText = context.coordinator.lastPlainText != plainText
        let wasNearBottom = context.coordinator.isNearBottom(textView)
        let previousOffset = textView.contentOffset

        textView.backgroundColor = backgroundColor
        textView.indicatorStyle = isDark(backgroundColor) ? .white : .black
        textView.font = font

        if didChangeText || didChangeResetKey {
            textView.attributedText = preparedAttributedText(font: font)
            context.coordinator.lastPlainText = plainText
            context.coordinator.lastResetKey = resetKey
        }

        if scrollTopRequestID != context.coordinator.lastScrollTopRequestID {
            context.coordinator.lastScrollTopRequestID = scrollTopRequestID
            context.coordinator.scrollToTop(textView)
        } else if scrollBottomRequestID != context.coordinator.lastScrollBottomRequestID {
            context.coordinator.lastScrollBottomRequestID = scrollBottomRequestID
            context.coordinator.scrollToBottom(textView)
        } else if didChangeText || didChangeResetKey {
            if !context.coordinator.didInitialScroll || didChangeResetKey || wasNearBottom {
                context.coordinator.scrollToBottom(textView)
                context.coordinator.didInitialScroll = true
            } else {
                context.coordinator.restore(previousOffset, in: textView)
            }
        }
    }

    private func preparedAttributedText(font: UIFont) -> NSAttributedString {
        let rendered = NSMutableAttributedString(attributedString: NSAttributedString(attributedText))
        guard rendered.length > 0 else {
            return NSAttributedString(string: " ", attributes: [.font: font])
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.lineSpacing = 1
        let fullRange = NSRange(location: 0, length: rendered.length)
        rendered.addAttributes([
            .font: font,
            .paragraphStyle: paragraph,
        ], range: fullRange)
        return rendered
    }

    private func isDark(_ color: UIColor) -> Bool {
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        if color.getWhite(&white, alpha: &alpha) {
            return white < 0.5
        }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            return (red * 0.299 + green * 0.587 + blue * 0.114) < 0.5
        }
        return false
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var lastPlainText = ""
        var lastResetKey = ""
        var lastScrollTopRequestID = 0
        var lastScrollBottomRequestID = 0
        var didInitialScroll = false

        func isNearBottom(_ textView: UITextView) -> Bool {
            let maxY = maxVerticalOffset(textView)
            return maxY - textView.contentOffset.y < 48
        }

        func scrollToTop(_ textView: UITextView) {
            textView.layoutIfNeeded()
            textView.setContentOffset(CGPoint(x: 0, y: -textView.adjustedContentInset.top), animated: false)
        }

        func scrollToBottom(_ textView: UITextView) {
            textView.layoutIfNeeded()
            let y = maxVerticalOffset(textView)
            textView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }

        func restore(_ offset: CGPoint, in textView: UITextView) {
            textView.layoutIfNeeded()
            let y = min(max(offset.y, -textView.adjustedContentInset.top), maxVerticalOffset(textView))
            textView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }

        private func maxVerticalOffset(_ textView: UITextView) -> CGFloat {
            max(-textView.adjustedContentInset.top, textView.contentSize.height + textView.adjustedContentInset.bottom - textView.bounds.height)
        }
    }
}
