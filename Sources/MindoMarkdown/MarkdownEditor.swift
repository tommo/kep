import AppKit
import SwiftUI
import WebKit
import Combine
import UniformTypeIdentifiers
import MindoBase
import MindoCore

/// Split editor view: NSTextView (left) + WKWebView preview (right). Mirrors the
/// `MarkdownEditor` layout in `mindolph-markdown`.
public struct MarkdownEditor: NSViewRepresentable {
    @Binding public var text: String
    public var isDarkMode: Bool
    /// External navigation hint — string-encoded UTF-8 byte offset (matches
    /// `Outline.fromMarkdown`). When this changes, scroll the text view.
    public var navigationTarget: String?
    /// On-disk URL of the document being edited, when it has one. Used as
    /// the preview's `baseURL` so relative image/link references (e.g.
    /// `![](images/diagram.png)`) resolve against the document's folder
    /// instead of failing to load (the bug: baseURL was always nil).
    public var documentURL: URL?
    /// Workspace document names offered when autocompleting a `[[wiki link]]`.
    /// Defaults to none, so the editor only surfaces knowledge-base completions
    /// where the app wires up a workspace file list.
    public var wikiLinkCandidates: () -> [String]
    /// Invoked when a `[[wiki link]]` is clicked in the preview: (target, heading?).
    /// The host resolves the target to a workspace doc and opens it.
    public var onOpenWikiLink: ((String, String?) -> Void)?

    public init(text: Binding<String>, isDarkMode: Bool = false, navigationTarget: String? = nil, documentURL: URL? = nil,
                wikiLinkCandidates: @escaping () -> [String] = { [] },
                onOpenWikiLink: ((String, String?) -> Void)? = nil) {
        self._text = text
        self.isDarkMode = isDarkMode
        self.navigationTarget = navigationTarget
        self.documentURL = documentURL
        self.wikiLinkCandidates = wikiLinkCandidates
        self.onOpenWikiLink = onOpenWikiLink
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let split = NSSplitView()
        split.isVertical = PrefKeys.bool(PrefKeys.markdownSplitVertical, fallback: true)
        split.dividerStyle = .thin

        // Status footer — words / chars / cursor position.
        let footer = NSTextField(labelWithString: "")
        footer.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        footer.textColor = .secondaryLabelColor
        footer.alignment = .right
        footer.translatesAutoresizingMaskIntoConstraints = false

        // Preview layout switch: none (editor only) / side-by-side / stacked.
        let modeControl = PreviewModeControl.make(target: context.coordinator,
                                                   action: #selector(Coordinator.previewModeChanged(_:)))
        context.coordinator.modeControl = modeControl

        split.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(split)
        container.addSubview(modeControl)
        container.addSubview(footer)
        // No format toolbar — it was visual clutter; bold/italic/code/link stay
        // on ⌘B / ⌘I / ⌘E / ⌘K. The editor fills from the top.
        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: container.topAnchor),
            split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: modeControl.topAnchor, constant: -2),
            modeControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            modeControl.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
            footer.centerYAnchor.constraint(equalTo: modeControl.centerYAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            footer.leadingAnchor.constraint(greaterThanOrEqualTo: modeControl.trailingAnchor, constant: 8),
        ])
        context.coordinator.statusFooter = footer

        // Left: code editor — drop-aware subclass turns dropped image / text
        // files into the appropriate markdown snippet.
        let (scroll, textView) = CodeArea.makeMonospaced(
            text: text,
            delegate: context.coordinator,
            textViewFactory: { MarkdownDropTextView(frame: .zero) }
        )
        if let dropView = textView as? MarkdownDropTextView {
            dropView.wikiLinkCandidates = wikiLinkCandidates
        }
        textView.usesFontPanel = false
        textView.autoresizingMask = [.width]
        textView.translatesAutoresizingMaskIntoConstraints = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
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
        webConfig.userContentController.add(context.coordinator, name: "previewAnchor")
        let web = MarkdownPreviewWebView(frame: .zero, configuration: webConfig)
        web.setValue(false, forKey: "drawsBackground") // KVO trick to make transparent
        web.navigationDelegate = context.coordinator
        web.menuItemsProvider = { PreviewContextMenu.markdown() }
        web.onMenuAction = { [weak coordinator = context.coordinator] action in
            coordinator?.handlePreviewMenuAction(action)
        }

        split.addArrangedSubview(scroll)
        split.addArrangedSubview(web)
        split.setHoldingPriority(NSLayoutConstraint.Priority(rawValue: 250), forSubviewAt: 0)

        context.coordinator.textView = textView
        context.coordinator.webView = web
        context.coordinator.splitView = split
        context.coordinator.editorScroll = scroll
        context.coordinator.applyHighlighting()
        context.coordinator.refreshStatusFooter()
        context.coordinator.refreshPreview()
        context.coordinator.applyViewMode(context.coordinator.viewMode, persist: false)
        return container
    }


    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        // Re-highlight only when something that affects styling actually
        // changed — the text body or the light/dark theme. The old code ran a
        // full-document highlight on *every* SwiftUI update pass (which fire
        // for many unrelated reasons), doubling the per-keystroke cost.
        if let tv = context.coordinator.textView, tv.string != text {
            tv.string = text
            context.coordinator.applyHighlighting()
            context.coordinator.refreshPreview()
        } else if context.coordinator.lastHighlightedDarkMode != isDarkMode {
            context.coordinator.applyHighlighting()
        }
        context.coordinator.lastHighlightedDarkMode = isDarkMode
        if let target = navigationTarget, target != context.coordinator.lastNavigated {
            context.coordinator.lastNavigated = target
            DispatchQueue.main.async { context.coordinator.scroll(toByteOffsetString: target) }
        }
        context.coordinator.placeDividerIfNeeded()
    }

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public final class Coordinator: NSObject, NSTextViewDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: MarkdownEditor
        var textView: NSTextView?
        var webView: WKWebView?
        weak var statusFooter: NSTextField?
        weak var splitView: NSSplitView?
        weak var editorScroll: NSScrollView?
        /// Current pane layout. Persisted to `PrefKeys.markdownViewMode`.
        var viewMode: MarkdownViewMode = .from(rawValue: PrefKeys.string(PrefKeys.markdownViewMode))
        var lastNavigated: String?
        let highlighter = MarkdownHighlighter()
        private let previewDebouncer = Debouncer()
        private let statsDebouncer = Debouncer()
        /// Suppress reciprocal scroll mirroring while we're programmatically
        /// driving one side. Counted both ways to avoid feedback loops.
        private var ignoreTextScroll = false
        private var ignorePreviewScroll = false
        private var didPlaceDivider = false
        weak var modeControl: NSSegmentedControl?

        /// Footer preview-layout switch: 0 none, 1 side-by-side, 2 stacked.
        @objc func previewModeChanged(_ sender: NSSegmentedControl) {
            switch sender.selectedSegment {
            case 0: applyViewMode(.editor)
            case 1: setSplitVertical(true);  applyViewMode(.split)
            case 2: setSplitVertical(false); applyViewMode(.split)
            default: break
            }
        }

        private func setSplitVertical(_ vertical: Bool) {
            splitView?.isVertical = vertical
            UserDefaults.standard.set(vertical, forKey: PrefKeys.markdownSplitVertical)
            didPlaceDivider = false   // re-center for the new orientation
        }

        func syncModeControl() {
            modeControl?.selectedSegment = (viewMode != .split)
                ? 0 : ((splitView?.isVertical ?? true) ? 1 : 2)
        }

        /// An NSSplitView with two arranged subviews and no explicit position
        /// can leave the preview pane collapsed to zero width (→ "no preview").
        /// Place the divider at 50% once, after the split has a real size.
        func placeDividerIfNeeded() {
            guard !didPlaceDivider, viewMode == .split, let split = splitView else { return }
            let dim = split.isVertical ? split.bounds.width : split.bounds.height
            guard dim > 1 else { return }
            didPlaceDivider = true
            split.setPosition(dim * 0.5, ofDividerAt: 0)
        }

        // MARK: - Toolbar actions

        @objc func toolbarBold()       { applyTransform(MarkdownFormatting.bold) }
        @objc func toolbarItalic()     { applyTransform(MarkdownFormatting.italic) }
        @objc func toolbarInlineCode() { applyTransform(MarkdownFormatting.inlineCode) }
        @objc func toolbarLink() {
            guard let url = promptString(title: "Insert Link", message: "URL:", initial: "https://") else { return }
            applyTransform { MarkdownFormatting.link($0, range: $1, url: url) }
        }
        @objc func toolbarHeading1()      { applyTransform { MarkdownFormatting.heading($0, range: $1, level: 1) } }
        @objc func toolbarHeading2()      { applyTransform { MarkdownFormatting.heading($0, range: $1, level: 2) } }
        @objc func toolbarHeading3()      { applyTransform { MarkdownFormatting.heading($0, range: $1, level: 3) } }
        @objc func toolbarQuote()         { applyTransform(MarkdownFormatting.blockquote) }
        @objc func toolbarHorizontalRule() { applyTransform(MarkdownFormatting.horizontalRule) }
        @objc func toolbarComment()       { applyTransform(MarkdownFormatting.comment) }
        @objc func toolbarTable() {
            guard let (rows, cols) = promptTableSize() else { return }
            applyTransform { MarkdownFormatting.table($0, range: $1, rows: rows, cols: cols) }
        }

        @objc func toolbarImage() {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.image]
            guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
            let snippet = MarkdownDropFormatter.snippet(for: panel.urls, relativeToFileAt: parent.documentURL)
            guard !snippet.isEmpty else { return }
            applyTransform { text, range in
                let ns = text as NSString
                let newText = ns.replacingCharacters(in: range, with: snippet)
                let caret = NSRange(location: range.location + (snippet as NSString).length, length: 0)
                return (newText, caret)
            }
        }

        /// Rows/cols prompt for table insertion — two small fields in an
        /// NSAlert accessory. Returns nil on Cancel; values clamped to 1…20.
        private func promptTableSize() -> (rows: Int, cols: Int)? {
            let alert = NSAlert()
            alert.messageText = "Insert Table"
            alert.informativeText = "Number of rows and columns:"
            let rows = NSTextField(string: "2")
            let cols = NSTextField(string: "3")
            for f in [rows, cols] { f.alignment = .center; f.translatesAutoresizingMaskIntoConstraints = false }
            func label(_ s: String) -> NSTextField {
                let l = NSTextField(labelWithString: s)
                l.translatesAutoresizingMaskIntoConstraints = false
                return l
            }
            let stack = NSStackView(views: [label("Rows"), rows, label("Cols"), cols])
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.frame = NSRect(x: 0, y: 0, width: 260, height: 26)
            NSLayoutConstraint.activate([rows.widthAnchor.constraint(equalToConstant: 48),
                                         cols.widthAnchor.constraint(equalToConstant: 48)])
            alert.accessoryView = stack
            alert.addButton(withTitle: "Insert")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            return MarkdownFormatBridge.sanitizedTableSize(rows: rows.stringValue, cols: cols.stringValue)
        }

        /// Show/hide the editor and preview panes for `mode`. NSSplitView
        /// honours `isHidden` on its arranged subviews, collapsing the hidden
        /// one and giving the other the full area. Re-renders the preview when
        /// it becomes visible so a preview-only switch isn't stale.
        func applyViewMode(_ mode: MarkdownViewMode, persist: Bool = true) {
            viewMode = mode
            editorScroll?.isHidden = !mode.showsEditor
            webView?.isHidden = !mode.showsPreview
            splitView?.adjustSubviews()
            if mode.showsPreview { refreshPreview() }
            placeDividerIfNeeded()
            syncModeControl()
            if persist {
                UserDefaults.standard.set(mode.rawValue, forKey: PrefKeys.markdownViewMode)
            }
        }


        /// One-line text-field prompt — returns nil on Cancel or empty input.
        private func promptString(title: String, message: String, initial: String) -> String? {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            let field = NSTextField(string: initial)
            field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            alert.accessoryView = field
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        /// MIME type lookup for the small set of image formats `NSOpenPanel`
        /// surfaces. Static so it's testable independently.
        public static func mimeType(for ext: String) -> String {
            switch ext {
            case "png": return "image/png"
            case "jpg", "jpeg": return "image/jpeg"
            case "gif": return "image/gif"
            case "svg": return "image/svg+xml"
            case "webp": return "image/webp"
            default: return "application/octet-stream"
            }
        }

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

        private var themeObserver: NSObjectProtocol?

        init(parent: MarkdownEditor) {
            self.parent = parent
            super.init()
            // Live-restyle when the user edits the custom editor theme.
            themeObserver = NotificationCenter.default.addObserver(
                forName: .editorThemeChanged, object: nil, queue: .main
            ) { [weak self] _ in self?.applyHighlighting() }
        }

        deinit {
            if let themeObserver { NotificationCenter.default.removeObserver(themeObserver) }
        }

        public func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            applyHighlighting()
            // Debounce preview re-rendering — typing should feel snappy.
            previewDebouncer.schedule(after: 0.15) { [weak self] in self?.refreshPreview() }
            // Word/char count: 250ms throttle so the footer doesn't churn on
            // every keystroke for large documents.
            statsDebouncer.schedule(after: 0.25) { [weak self] in self?.refreshStatusFooter() }
        }

        /// Recompute the words / chars footer for the current text view body.
        /// Public-internal so initial display + the change handler can both fire it.
        func refreshStatusFooter() {
            guard let footer = statusFooter, let body = textView?.string else { return }
            let stats = MarkdownStats.compute(body)
            footer.stringValue = "\(stats.words) words · \(stats.characters) chars"
        }

        /// Tracks the theme the storage was last highlighted with, so an
        /// unrelated SwiftUI update pass doesn't trigger a redundant full
        /// re-highlight when only the theme could have changed.
        var lastHighlightedDarkMode: Bool?

        func applyHighlighting() {
            guard let storage = textView?.textStorage else { return }
            highlighter.theme = .resolved(dark: parent.isDarkMode)
            highlighter.highlight(storage, activeRange: textView?.selectedRange())
            lastHighlightedDarkMode = parent.isDarkMode
        }

        private var lastActiveParagraph: NSRange?

        /// Re-reveal/hide markup when the caret moves to a different paragraph
        /// (Obsidian shows the raw markup only on the line you're editing).
        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            let para = (tv.string as NSString).paragraphRange(for: tv.selectedRange())
            if para != lastActiveParagraph {
                lastActiveParagraph = para
                applyHighlighting()
            }
        }

        /// Route a preview right-click action. Refresh re-renders; Focus
        /// Editor returns the caret to the source pane.
        func handlePreviewMenuAction(_ action: PreviewMenuAction) {
            switch action {
            case .refresh:    refreshPreview()
            case .viewSource: textView?.window?.makeFirstResponder(textView)
            case .copyHTML:   MarkdownExporter.copyHTMLToPasteboard(markdown: parent.text)
            default:          break   // SVG/PNG/script/export are PlantUML-only
            }
        }

        func refreshPreview() {
            guard let web = webView else { return }
            let html = MarkdownRenderer.render(markdown: parent.text)
            // baseURL = the document's folder so relative image/link refs
            // (e.g. ![](img/x.png)) resolve. nil for unsaved docs.
            let base = MarkdownPreviewBase.baseURL(forDocumentAt: parent.documentURL)
            web.loadHTMLString(html, baseURL: base)
        }

        /// Intercept link clicks in the preview. Without this, clicking any
        /// link navigated the WKWebView away from the rendered markdown
        /// (the preview "swallowed" the click). External links open in the
        /// system browser; file links open in the default app; in-page
        /// anchors and the initial render still load in place.
        public func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let isClick = navigationAction.navigationType == .linkActivated
            // Wiki links resolve in-app to a workspace document.
            if isClick, let url = navigationAction.request.url, url.scheme == WikiLinkMarkdown.scheme,
               let decoded = WikiLinkMarkdown.decode(url.absoluteString) {
                parent.onOpenWikiLink?(decoded.target, decoded.heading)
                decisionHandler(.cancel)
                return
            }
            switch MarkdownLinkPolicy.decide(url: navigationAction.request.url, isLinkActivation: isClick) {
            case .allow:
                decisionHandler(.allow)
            case .openExternally(let url), .openFile(let url):
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            }
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

        /// Preview reported either a scroll fraction or an anchor click.
        public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            switch message.name {
            case "previewScroll":
                handlePreviewScroll(message.body)
            case "previewAnchor":
                if let slug = message.body as? String { scrollCodeArea(toAnchor: slug) }
            default:
                break
            }
        }

        private func handlePreviewScroll(_ body: Any) {
            if ignorePreviewScroll { return }
            guard let raw = body as? Double else { return }
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

        /// Find the heading whose slug matches `slug` and scroll the code
        /// area to its line. Mirrors mindolph's HTMLAnchorElement listener.
        private func scrollCodeArea(toAnchor slug: String) {
            guard let tv = textView else { return }
            let nsString = tv.string as NSString
            var byteOffset = 0
            for line in tv.string.split(separator: "\n", omittingEmptySubsequences: false) {
                let raw = String(line)
                if let heading = headingTitle(in: raw),
                   MarkdownRenderer.slugify(heading) == slug {
                    let location = min(nsString.length, byteOffset)
                    let lineRange = nsString.lineRange(for: NSRange(location: location, length: 0))
                    tv.scrollRangeToVisible(lineRange)
                    tv.setSelectedRange(lineRange)
                    tv.window?.makeFirstResponder(tv)
                    return
                }
                byteOffset += (raw as NSString).length + 1   // +1 for the '\n' we split on
            }
        }

        private func headingTitle(in line: String) -> String? {
            var idx = line.startIndex
            var depth = 0
            while idx < line.endIndex, line[idx] == "#", depth < 6 {
                idx = line.index(after: idx)
                depth += 1
            }
            guard depth >= 1, idx < line.endIndex, line[idx] == " " else { return nil }
            return String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        }
    }
}
