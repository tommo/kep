import AppKit
import SwiftUI
import WebKit
import Combine
import MindoBase

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
        let (scroll, textView) = CodeArea.makeMonospaced(text: text, delegate: context.coordinator)
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
        stack.addArrangedSubview(makeVerticalDivider())
        stack.addArrangedSubview(iconButton(symbol: "strikethrough", tooltip: "Strikethrough", action: #selector(Coordinator.toolbarStrikethrough)))
        stack.addArrangedSubview(iconButton(symbol: "tablecells", tooltip: "Table", action: #selector(Coordinator.toolbarTable)))
        stack.addArrangedSubview(iconButton(symbol: "captions.bubble", tooltip: "HTML comment", action: #selector(Coordinator.toolbarComment)))
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
        private let previewDebouncer = Debouncer()
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
        @objc func toolbarLink() {
            guard let url = promptString(title: "Insert Link", message: "URL:", initial: "https://") else { return }
            applyTransform { MarkdownFormatting.link($0, range: $1, url: url) }
        }
        @objc func toolbarStrikethrough() { applyTransform(MarkdownFormatting.strikethrough) }
        @objc func toolbarComment()       { applyTransform(MarkdownFormatting.comment) }
        @objc func toolbarTable() {
            // Picker dialog with rows + cols steppers + alignment segmented
            // control. Mirrors mindolph's TableDialog at the input level.
            let alert = NSAlert()
            alert.messageText = "Insert Table"
            alert.informativeText = "Pick the table size and column alignment."

            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 8
            stack.frame = NSRect(x: 0, y: 0, width: 320, height: 100)

            let rowsRow = NSStackView()
            rowsRow.orientation = .horizontal
            rowsRow.spacing = 8
            let rowsLabel = NSTextField(labelWithString: "Rows:")
            rowsLabel.frame.size.width = 60
            let rowsField = NSTextField(string: "3"); rowsField.frame.size.width = 48; rowsField.alignment = .right
            let rowsStepper = NSStepper(); rowsStepper.minValue = 1; rowsStepper.maxValue = 30; rowsStepper.integerValue = 3
            rowsStepper.target = self; rowsStepper.action = #selector(syncStepperToField(_:))
            stepperFieldMap[ObjectIdentifier(rowsStepper)] = rowsField
            rowsRow.addArrangedSubview(rowsLabel); rowsRow.addArrangedSubview(rowsField); rowsRow.addArrangedSubview(rowsStepper)

            let colsRow = NSStackView()
            colsRow.orientation = .horizontal
            colsRow.spacing = 8
            let colsLabel = NSTextField(labelWithString: "Columns:")
            colsLabel.frame.size.width = 60
            let colsField = NSTextField(string: "3"); colsField.frame.size.width = 48; colsField.alignment = .right
            let colsStepper = NSStepper(); colsStepper.minValue = 1; colsStepper.maxValue = 12; colsStepper.integerValue = 3
            colsStepper.target = self; colsStepper.action = #selector(syncStepperToField(_:))
            stepperFieldMap[ObjectIdentifier(colsStepper)] = colsField
            colsRow.addArrangedSubview(colsLabel); colsRow.addArrangedSubview(colsField); colsRow.addArrangedSubview(colsStepper)

            let alignRow = NSStackView()
            alignRow.orientation = .horizontal
            alignRow.spacing = 8
            let alignLabel = NSTextField(labelWithString: "Align:")
            alignLabel.frame.size.width = 60
            let alignSeg = NSSegmentedControl(labels: ["Default", "Left", "Center", "Right"], trackingMode: .selectOne, target: nil, action: nil)
            alignSeg.selectedSegment = 0
            alignRow.addArrangedSubview(alignLabel); alignRow.addArrangedSubview(alignSeg)

            stack.addArrangedSubview(rowsRow)
            stack.addArrangedSubview(colsRow)
            stack.addArrangedSubview(alignRow)
            alert.accessoryView = stack
            alert.addButton(withTitle: "Insert")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            let rows = max(1, Int(rowsField.stringValue) ?? rowsStepper.integerValue)
            let cols = max(1, Int(colsField.stringValue) ?? colsStepper.integerValue)
            let alignment: MarkdownFormatting.TableAlignment
            switch alignSeg.selectedSegment {
            case 1: alignment = .left
            case 2: alignment = .center
            case 3: alignment = .right
            default: alignment = .none
            }
            applyTransform { MarkdownFormatting.table($0, range: $1, rows: rows, cols: cols, alignment: alignment) }
        }

        /// Backing map so the stepper action can find its sibling field.
        private var stepperFieldMap: [ObjectIdentifier: NSTextField] = [:]

        @objc private func syncStepperToField(_ sender: NSStepper) {
            stepperFieldMap[ObjectIdentifier(sender)]?.stringValue = String(sender.integerValue)
        }

        @objc func toolbarImage() {
            // Two-button alert: paste URL or pick a local file (NSOpenPanel
            // → base64-encoded data: URL for offline embedding).
            let alert = NSAlert()
            alert.messageText = "Insert Image"
            alert.informativeText = "Paste a URL, or choose a local file to embed as data:"
            let field = NSTextField(string: "https://")
            field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            alert.accessoryView = field
            alert.addButton(withTitle: "Insert URL")
            alert.addButton(withTitle: "Choose File…")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let url = field.stringValue
                guard !url.isEmpty else { return }
                applyTransform { MarkdownFormatting.image($0, range: $1, url: url) }
            case .alertSecondButtonReturn:
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image, .png, .jpeg, .gif]
                panel.allowsMultipleSelection = false
                guard panel.runModal() == .OK, let fileURL = panel.url else { return }
                guard let data = try? Data(contentsOf: fileURL) else { return }
                let mime = Self.mimeType(for: fileURL.pathExtension.lowercased())
                let dataURL = "data:\(mime);base64,\(data.base64EncodedString())"
                applyTransform { MarkdownFormatting.image($0, range: $1, url: dataURL) }
            default:
                return
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

        init(parent: MarkdownEditor) { self.parent = parent }

        public func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            applyHighlighting()
            // Debounce preview re-rendering — typing should feel snappy.
            previewDebouncer.schedule(after: 0.15) { [weak self] in self?.refreshPreview() }
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
