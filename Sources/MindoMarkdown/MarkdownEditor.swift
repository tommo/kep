import AppKit
import SwiftUI
import WebKit
import Combine

/// Split editor view: NSTextView (left) + WKWebView preview (right). Mirrors the
/// `MarkdownEditor` layout in `mindolph-markdown`.
public struct MarkdownEditor: NSViewRepresentable {
    @Binding public var text: String
    public var isDarkMode: Bool

    public init(text: Binding<String>, isDarkMode: Bool = false) {
        self._text = text
        self.isDarkMode = isDarkMode
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
    }

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public final class Coordinator: NSObject, NSTextViewDelegate, WKNavigationDelegate {
        var parent: MarkdownEditor
        var textView: NSTextView?
        var webView: WKWebView?
        let highlighter = MarkdownHighlighter()
        private var debounceWorkItem: DispatchWorkItem?

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
