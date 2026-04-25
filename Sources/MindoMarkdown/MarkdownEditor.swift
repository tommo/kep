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

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let toolbar = makeToolbar(coordinator: context.coordinator)

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        split.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbar)
        container.addSubview(split)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            split.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

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
        // Track text-view scrolling so we can mirror to the preview.
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textScrollDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )

        // Right: WKWebView preview with a JS bridge that reports user scrolls
        // back to the host so we can echo them into the code area.
        let webConfig = WKWebViewConfiguration()
        webConfig.userContentController.add(context.coordinator, name: "previewScroll")
        let web = WKWebView(frame: .zero, configuration: webConfig)
        web.setValue(false, forKey: "drawsBackground") // KVO trick to make transparent
        web.navigationDelegate = context.coordinator

        split.addArrangedSubview(scroll)
        split.addArrangedSubview(web)
        split.setHoldingPriority(NSLayoutConstraint.Priority(rawValue: 250), forSubviewAt: 0)

        context.coordinator.textView = textView
        context.coordinator.webView = web
        context.coordinator.applyHighlighting()
        context.coordinator.refreshPreview()
        return container
    }

    private func makeVerticalDivider() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: 1).isActive = true
        box.heightAnchor.constraint(equalToConstant: 18).isActive = true
        return box
    }

    private func makeToolbar(coordinator: Coordinator) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.alignment = .centerY

        func iconButton(symbol: String, tooltip: String, action: Selector) -> NSButton {
            let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
            let b = NSButton(image: img ?? NSImage(), target: coordinator, action: action)
            b.bezelStyle = .accessoryBarAction
            b.toolTip = tooltip
            return b
        }
        stack.addArrangedSubview(iconButton(symbol: "bold", tooltip: "Bold", action: #selector(Coordinator.toolbarBold)))
        stack.addArrangedSubview(iconButton(symbol: "italic", tooltip: "Italic", action: #selector(Coordinator.toolbarItalic)))
        stack.addArrangedSubview(iconButton(symbol: "chevron.left.forwardslash.chevron.right", tooltip: "Inline code", action: #selector(Coordinator.toolbarInlineCode)))
        stack.addArrangedSubview(makeVerticalDivider())
        stack.addArrangedSubview(iconButton(symbol: "1.square", tooltip: "Heading 1", action: #selector(Coordinator.toolbarH1)))
        stack.addArrangedSubview(iconButton(symbol: "2.square", tooltip: "Heading 2", action: #selector(Coordinator.toolbarH2)))
        stack.addArrangedSubview(iconButton(symbol: "3.square", tooltip: "Heading 3", action: #selector(Coordinator.toolbarH3)))
        stack.addArrangedSubview(makeVerticalDivider())
        stack.addArrangedSubview(iconButton(symbol: "list.bullet", tooltip: "Bullet list", action: #selector(Coordinator.toolbarBullet)))
        stack.addArrangedSubview(iconButton(symbol: "list.number", tooltip: "Numbered list", action: #selector(Coordinator.toolbarNumbered)))
        stack.addArrangedSubview(iconButton(symbol: "text.quote", tooltip: "Quote", action: #selector(Coordinator.toolbarQuote)))
        stack.addArrangedSubview(makeVerticalDivider())
        stack.addArrangedSubview(iconButton(symbol: "link", tooltip: "Link", action: #selector(Coordinator.toolbarLink)))
        stack.addArrangedSubview(iconButton(symbol: "photo", tooltip: "Image", action: #selector(Coordinator.toolbarImage)))
        stack.addArrangedSubview(NSView())  // spacer
        return stack
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
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

    public final class Coordinator: NSObject, NSTextViewDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownEditor
        var textView: NSTextView?
        var webView: WKWebView?
        var lastNavigated: String?
        let highlighter = MarkdownHighlighter()
        private var debounceWorkItem: DispatchWorkItem?
        /// Suppress reciprocal scroll mirroring while we're programmatically
        /// driving one side. Counted both ways to avoid feedback loops.
        private var ignoreTextScroll = false
        private var ignorePreviewScroll = false

        // MARK: - Toolbar actions

        @objc func toolbarBold()       { applyTransform(MarkdownFormatting.bold) }
        @objc func toolbarItalic()     { applyTransform(MarkdownFormatting.italic) }
        @objc func toolbarInlineCode() { applyTransform(MarkdownFormatting.inlineCode) }
        @objc func toolbarH1()         { applyTransform { MarkdownFormatting.heading($0, range: $1, level: 1) } }
        @objc func toolbarH2()         { applyTransform { MarkdownFormatting.heading($0, range: $1, level: 2) } }
        @objc func toolbarH3()         { applyTransform { MarkdownFormatting.heading($0, range: $1, level: 3) } }
        @objc func toolbarBullet()     { applyTransform(MarkdownFormatting.bulletList) }
        @objc func toolbarNumbered()   { applyTransform(MarkdownFormatting.numberedList) }
        @objc func toolbarQuote()      { applyTransform(MarkdownFormatting.blockquote) }
        @objc func toolbarLink()       { applyTransform { MarkdownFormatting.link($0, range: $1, url: "https://") } }
        @objc func toolbarImage()      { applyTransform { MarkdownFormatting.image($0, range: $1, url: "https://") } }

        private func applyTransform(_ transform: (String, NSRange) -> (String, NSRange)) {
            guard let tv = textView else { return }
            let (newText, newRange) = transform(tv.string, tv.selectedRange())
            tv.string = newText
            tv.setSelectedRange(newRange)
            parent.text = newText
            applyHighlighting()
            refreshPreview()
        }

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

        // MARK: - Scroll sync

        /// Compute the current code-area scroll fraction (0…1).
        private func textScrollFraction() -> CGFloat {
            guard let scroll = textView?.enclosingScrollView else { return 0 }
            let visible = scroll.contentView.bounds
            let document = scroll.documentView?.frame ?? .zero
            let denom = max(1, document.height - visible.height)
            return min(1, max(0, visible.minY / denom))
        }

        /// Code-area scrolled — mirror the fraction to the preview, unless
        /// the preview just told us to scroll.
        @objc func textScrollDidChange(_ note: Notification) {
            if ignoreTextScroll { return }
            let f = textScrollFraction()
            ignorePreviewScroll = true
            webView?.evaluateJavaScript("window.mindoScrollTo && mindoScrollTo(\(f))", completionHandler: nil)
            // Tiny grace window so the bounce-back from the preview's scroll
            // event handler doesn't flip us.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.ignorePreviewScroll = false
            }
        }

        /// Preview reported a user scroll — mirror the fraction back to the
        /// code area (unless we're the ones driving it).
        public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "previewScroll" else { return }
            if ignorePreviewScroll { return }
            guard let raw = message.body as? Double else { return }
            let f: CGFloat = CGFloat(raw)
            guard let scroll = textView?.enclosingScrollView else { return }
            let document = scroll.documentView?.frame ?? .zero
            let visible = scroll.contentView.bounds
            let target = max(0, (document.height - visible.height) * f)
            ignoreTextScroll = true
            scroll.contentView.scroll(to: NSPoint(x: 0, y: target))
            scroll.reflectScrolledClipView(scroll.contentView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.ignoreTextScroll = false
            }
        }
    }
}
