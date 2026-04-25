import AppKit
import SwiftUI
import WebKit
import Combine

/// Split editor view: NSTextView (left) + WKWebView preview (right). Mirrors the
/// `MarkdownEditor` layout in `mindolph-markdown`.
public struct MarkdownEditor: NSViewRepresentable {
    @Binding public var text: String
    public var isDarkMode: Bool
    /// External navigation hint — string-encoded UTF-8 byte offset (matches
    /// `Outline.fromMarkdown`). When this changes, scroll the text view.
    public var navigationTarget: String?

    public init(text: Binding<String>, isDarkMode: Bool = false, navigationTarget: String? = nil) {
        self._text = text
        self.isDarkMode = isDarkMode
        self.navigationTarget = navigationTarget
    }

    public func makeNSView(context: Context) -> NSSplitView {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin

        // Left: code editor
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let textView = NSTextView()
        textView.isRichText = false
        textView.isEditable = true
        textView.allowsUndo = true
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.autoresizingMask = [.width]
        textView.translatesAutoresizingMaskIntoConstraints = true
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.delegate = context.coordinator
        textView.string = text
        scroll.documentView = textView

        // Right: WKWebView preview
        let web = WKWebView()
        web.setValue(false, forKey: "drawsBackground") // KVO trick to make transparent
        web.navigationDelegate = context.coordinator

        split.addArrangedSubview(scroll)
        split.addArrangedSubview(web)
        split.setHoldingPriority(NSLayoutConstraint.Priority(rawValue: 250), forSubviewAt: 0)

        context.coordinator.textView = textView
        context.coordinator.webView = web
        context.coordinator.applyHighlighting()
        context.coordinator.refreshPreview()
        return split
    }

    public func updateNSView(_ nsView: NSSplitView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyHighlighting()
        if let tv = context.coordinator.textView, tv.string != text {
            tv.string = text
            context.coordinator.applyHighlighting()
            context.coordinator.refreshPreview()
        }
        if let target = navigationTarget, target != context.coordinator.lastNavigated {
            context.coordinator.lastNavigated = target
            DispatchQueue.main.async { context.coordinator.scroll(toByteOffsetString: target) }
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public final class Coordinator: NSObject, NSTextViewDelegate, WKNavigationDelegate {
        var parent: MarkdownEditor
        var textView: NSTextView?
        var webView: WKWebView?
        var lastNavigated: String?
        let highlighter = MarkdownHighlighter()
        private var debounceWorkItem: DispatchWorkItem?

        /// Convert a byte offset (string from Outline.fromMarkdown) to a UTF-16
        /// character offset, then scroll the text view to that range and
        /// select it. Tolerates clamped offsets so trailing edits don't crash.
        func scroll(toByteOffsetString s: String) {
            guard let byteOffset = Int(s), let tv = textView else { return }
            let nsString = tv.string as NSString
            let utf8 = tv.string.utf8
            let safeByte = max(0, min(byteOffset, utf8.count))
            // Map byte offset → string index by reading the UTF-8 view.
            var byteCount = 0
            var charIndex = 0
            for ch in tv.string {
                if byteCount >= safeByte { break }
                byteCount += ch.utf8.count
                charIndex += ch.utf16.count
            }
            let location = min(charIndex, nsString.length)
            // Pick the line range so the highlight covers the whole heading line.
            let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
            tv.scrollRangeToVisible(lineRange)
            tv.setSelectedRange(lineRange)
            tv.window?.makeFirstResponder(tv)
        }

        init(parent: MarkdownEditor) { self.parent = parent }

        public func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            applyHighlighting()
            // Debounce preview re-rendering — typing should feel snappy.
            debounceWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refreshPreview() }
            debounceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        func applyHighlighting() {
            guard let storage = textView?.textStorage else { return }
            highlighter.theme = parent.isDarkMode ? .dark : .light
            highlighter.highlight(storage)
        }

        func refreshPreview() {
            guard let web = webView else { return }
            let html = MarkdownRenderer.render(markdown: parent.text)
            web.loadHTMLString(html, baseURL: nil)
        }
    }
}
