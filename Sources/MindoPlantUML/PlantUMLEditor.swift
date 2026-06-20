import AppKit
import SwiftUI
import WebKit
import UniformTypeIdentifiers
import MindoBase
import MindoCore

/// Split editor for `.puml` files: NSTextView source on the left, WKWebView
/// preview of the rendered SVG on the right. Renders by shelling out to the
/// PlantUML CLI/jar via `PlantUMLRenderer`.
public struct PlantUMLEditor: NSViewRepresentable {
    @Binding public var text: String
    public var isDarkMode: Bool
    /// On-disk URL of the `.puml` being edited, when saved. Used only to
    /// seed the export save-panel's default filename.
    public var documentURL: URL?

    public init(text: Binding<String>, isDarkMode: Bool = false, documentURL: URL? = nil) {
        self._text = text
        self.isDarkMode = isDarkMode
        self.documentURL = documentURL
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        // Same frame behaviour as every other editor: compress horizontally
        // (toolbar clips) rather than forcing a wide minimum that collapses the
        // sidebar in this mode.
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let toolbar = makeToolbar(coordinator: context.coordinator)
        toolbar.clipsToBounds = true
        toolbar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let split = NSSplitView()
        split.isVertical = PrefKeys.bool(PrefKeys.plantumlSplitVertical, fallback: true)
        split.dividerStyle = .thin

        let (scroll, textView) = CodeArea.makeMonospaced(
            text: text,
            delegate: context.coordinator,
            textViewFactory: { PlantUMLTextView(frame: .zero) }
        )

        let web = PlantUMLPreviewWebView()
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        web.menuItemsProvider = { [weak coordinator = context.coordinator] in
            PreviewContextMenu.plantUML(hasRenderedDiagram: coordinator?.hasRenderedDiagram ?? false)
        }
        web.onMenuAction = { [weak coordinator = context.coordinator] action in
            coordinator?.handlePreviewMenuAction(action)
        }

        split.addArrangedSubview(scroll)
        split.addArrangedSubview(web)
        split.setHoldingPriority(NSLayoutConstraint.Priority(rawValue: 250), forSubviewAt: 0)

        // Status footer mirrors the markdown editor — line count is the most
        // useful quick stat for diagram source.
        let footer = NSTextField(labelWithString: "")
        footer.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        footer.textColor = .secondaryLabelColor
        footer.alignment = .right
        footer.translatesAutoresizingMaskIntoConstraints = false

        // Preview layout switch: none / side-by-side / stacked.
        let modeControl = PreviewModeControl.make(target: context.coordinator,
                                                   action: #selector(Coordinator.previewModeChanged(_:)))
        context.coordinator.modeControl = modeControl

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        split.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbar)
        container.addSubview(split)
        container.addSubview(modeControl)
        container.addSubview(footer)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            split.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: modeControl.topAnchor, constant: -2),
            modeControl.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
            modeControl.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
            footer.centerYAnchor.constraint(equalTo: modeControl.centerYAnchor),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            footer.leadingAnchor.constraint(greaterThanOrEqualTo: modeControl.trailingAnchor, constant: 8),
        ])

        context.coordinator.textView = textView
        context.coordinator.webView = web
        context.coordinator.splitView = split
        context.coordinator.statusFooter = footer
        context.coordinator.syncModeControl()
        context.coordinator.applyHighlighting()
        context.coordinator.refreshStatusFooter()
        context.coordinator.scheduleRender(immediate: true)
        return container
    }

    /// Toolbar with insert-skeleton buttons for the most-used PlantUML
    /// diagram types. Mirrors mindolph's PlantUmlToolbar at the
    /// "click → drop a skeleton at the cursor" level; the full snippet
    /// browser stays a future enhancement.

    private func makeToolbar(coordinator: Coordinator) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.alignment = .centerY
        // CRITICAL for layout stability: a horizontal stack of buttons reports
        // a minimum width = the sum of all button widths, and NSStackView
        // resists clipping that content at high priority by default. Pinned
        // edge-to-edge inside the editor, that minimum propagates up through the
        // NSHostingController and forces the (SwiftUI) detail pane wider —
        // squeezing the sidebar whenever a .puml tab is shown. Letting the stack
        // be clipped (low clipping resistance) means the toolbar yields instead
        // of the sidebar, so pane widths stay stable across document modes.
        stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        stack.setHuggingPriority(.defaultLow, for: .horizontal)

        // Compact icon button — image-only with a tooltip. A row of wide text
        // labels ("Use Case", "Copy SVG", …) was both unpolished and a big
        // chunk of the width that used to shove the sidebar aside.
        func iconButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
            let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
            let b = NSButton(title: "", target: coordinator, action: action)
            if let img { b.image = img; b.imagePosition = .imageOnly } else { b.title = tooltip }
            b.bezelStyle = .accessoryBarAction
            b.isBordered = false
            b.toolTip = tooltip
            return b
        }
        func divider() -> NSBox {
            let d = NSBox(); d.boxType = .separator
            d.translatesAutoresizingMaskIntoConstraints = false
            d.widthAnchor.constraint(equalToConstant: 1).isActive = true
            d.heightAnchor.constraint(equalToConstant: 18).isActive = true
            return d
        }

        // Insert-snippet menu, shown from a plain icon button. (A pull-down
        // NSPopUpButton rendered its empty title row as the literal
        // "NSMenuItem" — using a button + popUp(...) avoids that entirely.)
        stack.addArrangedSubview(iconButton("plus.rectangle.on.rectangle",
                                            tooltip: "Insert diagram snippet",
                                            action: #selector(Coordinator.showInsertMenu(_:))))

        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(iconButton("text.bubble", tooltip: "Toggle line comment (⌘/)", action: #selector(Coordinator.toggleLineComment)))
        stack.addArrangedSubview(iconButton("note.text", tooltip: "Insert block comment /' '/", action: #selector(Coordinator.insertBlockComment)))
        stack.addArrangedSubview(divider())
        stack.addArrangedSubview(iconButton("doc.on.doc", tooltip: "Copy rendered diagram as SVG", action: #selector(Coordinator.copyDiagramAsSVG)))
        stack.addArrangedSubview(iconButton("photo", tooltip: "Copy rendered diagram as PNG", action: #selector(Coordinator.copyDiagramAsPNG)))
        stack.addArrangedSubview(iconButton("square.and.arrow.up", tooltip: "Export rendered diagram to an SVG or PNG file", action: #selector(Coordinator.exportDiagram)))
        stack.addArrangedSubview(NSView())  // spacer
        return stack
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyHighlighting()
        let textChanged = context.coordinator.textView.map { $0.string != text } ?? false
        if let tv = context.coordinator.textView, textChanged {
            tv.string = text
            context.coordinator.applyHighlighting()
        }
        // Re-render on a text change OR a dark-mode flip — the preview HTML
        // bakes in theme colors, so a theme toggle alone left it stale (the
        // old code only checked text).
        let darkChanged = context.coordinator.lastRenderedDarkModeValue.map { $0 != isDarkMode } ?? false
        if PlantUMLPreviewState.shouldRerender(textChanged: textChanged, darkModeChanged: darkChanged) {
            context.coordinator.scheduleRender(immediate: true)
        }
        context.coordinator.placeDividerIfNeeded()
    }

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public final class Coordinator: NSObject, NSTextViewDelegate, WKNavigationDelegate {
        var parent: PlantUMLEditor
        var textView: NSTextView?
        var webView: WKWebView?
        weak var splitView: NSSplitView?
        weak var statusFooter: NSTextField?
        weak var modeControl: NSSegmentedControl?
        private var didPlaceDivider = false
        private var previewHidden = false
        let highlighter = PlantUMLHighlighter()

        /// Place the source/preview divider at 50% once the split has a real
        /// size — an NSSplitView with two arranged subviews and no explicit
        /// position can otherwise leave the preview collapsed to zero width.
        func placeDividerIfNeeded() {
            guard !didPlaceDivider, !previewHidden, let split = splitView else { return }
            let dim = split.isVertical ? split.bounds.width : split.bounds.height
            guard dim > 1 else { return }
            didPlaceDivider = true
            split.setPosition(dim * 0.5, ofDividerAt: 0)
        }

        /// Footer preview-layout switch: 0 none (hide preview), 1 side-by-side, 2 stacked.
        @objc func previewModeChanged(_ sender: NSSegmentedControl) {
            switch sender.selectedSegment {
            case 0:
                previewHidden = true
                webView?.isHidden = true
                splitView?.adjustSubviews()
            case 1:
                previewHidden = false; webView?.isHidden = false
                splitView?.isVertical = true
                UserDefaults.standard.set(true, forKey: PrefKeys.plantumlSplitVertical)
                didPlaceDivider = false
            case 2:
                previewHidden = false; webView?.isHidden = false
                splitView?.isVertical = false
                UserDefaults.standard.set(false, forKey: PrefKeys.plantumlSplitVertical)
                didPlaceDivider = false
            default: break
            }
            placeDividerIfNeeded()
        }

        func syncModeControl() {
            modeControl?.selectedSegment = previewHidden
                ? 0 : ((splitView?.isVertical ?? true) ? 1 : 2)
        }
        private let renderDebouncer = Debouncer()
        private let statsDebouncer = Debouncer()
        /// Most recent successful SVG render. Cached so the toolbar's Copy
        /// SVG / Copy PNG buttons don't re-shell out to PlantUML each time.
        private var lastSVGData: Data?
        /// Dark mode the preview was last rendered for. Lets updateNSView
        /// notice a theme flip and re-render (the preview HTML bakes in the
        /// background/foreground colors, so it's stale otherwise).
        private var lastRenderedDarkMode: Bool?
        /// Read-only peek for `updateNSView` (which lives on the struct, not
        /// the coordinator) to detect a theme flip. nil until the first render.
        var lastRenderedDarkModeValue: Bool? { lastRenderedDarkMode }

        /// Index of the diagram page (\@start…\@end block) shown in the preview.
        /// Multi-diagram files render one page at a time, switching as the caret
        /// moves between blocks (javamind parity).
        private var activePageIndex = 0
        /// Page count from the last render scan — drives the footer indicator.
        private var pageCount = 1

        /// Whether a diagram has successfully rendered — gates the preview
        /// context menu's Copy/Export items.
        var hasRenderedDiagram: Bool { PlantUMLClipboard.outcome(for: lastSVGData) == .copied }

        /// Route a preview right-click menu action to the matching toolbar
        /// behaviour. Refresh forces an immediate re-render.
        func handlePreviewMenuAction(_ action: PreviewMenuAction) {
            switch action {
            case .refresh:    scheduleRender(immediate: true)
            case .copySVG:    copyDiagramAsSVG()
            case .copyPNG:    copyDiagramAsPNG()
            case .copyScript: copyScript()
            case .export:     exportDiagram()
            case .viewSource: textView?.window?.makeFirstResponder(textView)
            case .copyHTML:   break   // markdown-only
            }
        }

        init(parent: PlantUMLEditor) { self.parent = parent }

        public func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            applyHighlighting()
            scheduleRender(immediate: false)
            statsDebouncer.schedule(after: 0.25) { [weak self] in self?.refreshStatusFooter() }
        }

        /// Caret moved — if it entered a different diagram page, switch the
        /// preview to that page (javamind's cursor-aware page tracking).
        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            let pages = PlantUMLPages.split(tv.string)
            guard pages.count > 1 else { return }
            let line = Self.lineIndex(of: tv.selectedRange().location, in: tv.string)
            guard let idx = PlantUMLPages.pageIndex(forLine: line, in: pages), idx != activePageIndex else { return }
            activePageIndex = idx
            scheduleRender(immediate: true)
            refreshStatusFooter()
        }

        /// 0-based line number containing character offset `loc`.
        static func lineIndex(of loc: Int, in string: String) -> Int {
            let end = string.index(string.startIndex, offsetBy: min(loc, string.count))
            return string[string.startIndex..<end].reduce(0) { $1 == "\n" ? $0 + 1 : $0 }
        }

        /// Recompute the line / char status footer for the current source.
        /// Lines are split on \n (one entry per visible line including blanks);
        /// chars are grapheme clusters so emoji + combining marks count once.
        func refreshStatusFooter() {
            guard let footer = statusFooter, let body = textView?.string else { return }
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false).count
            var status = "\(lines) lines · \(body.count) chars"
            if pageCount > 1 { status += " · page \(activePageIndex + 1)/\(pageCount)" }
            footer.stringValue = status
        }

        // MARK: - Toolbar actions

        /// Insert the catalog snippet whose body is carried on the menu item.
        @objc func insertCatalogSnippet(_ sender: NSMenuItem) {
            guard let body = sender.representedObject as? String else { return }
            insertSkeleton(body)
        }

        /// Pop up the snippet menu (one entry per catalog diagram type) beneath
        /// the toolbar's insert button.
        @objc func showInsertMenu(_ sender: NSButton) {
            let menu = NSMenu()
            for group in PlantUMLCatalog.groupedSnippets {
                let parent = NSMenuItem(title: group.category, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for snippet in group.snippets {
                    let it = NSMenuItem(title: snippet.title,
                                        action: #selector(insertCatalogSnippet(_:)), keyEquivalent: "")
                    it.target = self
                    it.representedObject = snippet.body
                    submenu.addItem(it)
                }
                parent.submenu = submenu
                menu.addItem(parent)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
        }

        /// Forward toolbar Comment to the textview so the same code path
        /// that handles ⌘/ runs (one undo entry, selection re-applied).
        @objc func toggleLineComment() {
            (textView as? PlantUMLTextView)?.toggleLineComment()
        }

        /// Insert an empty `/' '/` block at the cursor and place the
        /// caret on the inner blank line so the user can type immediately.
        @objc func insertBlockComment() {
            guard let tv = textView else { return }
            let range = tv.selectedRange()
            let nsText = tv.string as NSString
            let head = nsText.substring(to: range.location)
            let tail = nsText.substring(from: NSMaxRange(range))
            let leading = head.isEmpty || head.hasSuffix("\n") ? "" : "\n"
            let trailing = tail.hasPrefix("\n") || tail.isEmpty ? "" : "\n"
            let block = leading + "/'\n\n'/" + trailing
            let combined = head + block + tail
            tv.string = combined
            // Caret on the empty middle line: head + leading + "/'\n".
            let cursor = (head as NSString).length + (leading as NSString).length + 3
            tv.setSelectedRange(NSRange(location: cursor, length: 0))
            parent.text = combined
            applyHighlighting()
            scheduleRender(immediate: true)
        }

        /// Replace the current selection (or insert at the cursor) with
        /// `skeleton`, surrounded by the necessary blank lines so the
        /// renderer treats it as a top-level block. Updates the binding +
        /// re-renders.
        private func insertSkeleton(_ skeleton: String) {
            guard let tv = textView else { return }
            let range = tv.selectedRange()
            let nsText = tv.string as NSString
            let head = nsText.substring(to: range.location)
            let tail = nsText.substring(from: NSMaxRange(range))
            let leading = head.isEmpty || head.hasSuffix("\n\n") ? "" : (head.hasSuffix("\n") ? "\n" : "\n\n")
            let trailing = tail.hasPrefix("\n") ? "" : "\n"
            let block = leading + skeleton + trailing
            let combined = head + block + tail
            tv.string = combined
            let cursor = (head as NSString).length + (leading as NSString).length
            tv.setSelectedRange(NSRange(location: cursor, length: (skeleton as NSString).length))
            parent.text = combined
            applyHighlighting()
            scheduleRender(immediate: true)
        }

        func applyHighlighting() {
            guard let storage = textView?.textStorage else { return }
            highlighter.theme = parent.isDarkMode ? .dark : .light
            highlighter.highlight(storage)
        }

        func scheduleRender(immediate: Bool) {
            renderDebouncer.schedule(after: immediate ? 0.05 : 0.40) { [weak self] in
                self?.render()
            }
        }

        private func render() {
            guard let web = webView else { return }
            // Render just the active diagram page (the whole source when the
            // file holds a single — or no — @start…@end block).
            let pages = PlantUMLPages.split(parent.text)
            pageCount = pages.count
            if activePageIndex >= pages.count { activePageIndex = max(0, pages.count - 1) }
            let source = pages[activePageIndex].text
            let isDark = parent.isDarkMode
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let html: String
                var svgData: Data? = nil
                // Native lint first — catch structural mistakes (unbalanced
                // @start/@end, unclosed comments, unmatched control blocks) and
                // surface them with line numbers before we even try to render.
                let errors = PlantUMLDiagnostics.analyze(source).filter { $0.severity == .error }
                if !errors.isEmpty {
                    let msg = errors.map { "Line \($0.line): \($0.message)" }.joined(separator: "\n")
                    html = Self.errorHTML(message: msg, isDark: isDark)
                    DispatchQueue.main.async {
                        self?.lastRenderedDarkMode = isDark
                        web.loadHTMLString(html, baseURL: nil)
                    }
                    return
                }
                do {
                    let svg = try PlantUMLRenderer.shared.renderSVG(source: source, isDark: isDark)
                    svgData = svg
                    html = Self.previewHTML(svg: String(data: svg, encoding: .utf8) ?? "", isDark: isDark)
                } catch let err as PlantUMLRenderer.RenderError {
                    html = Self.errorHTML(message: err.errorDescription ?? "Unknown error", isDark: isDark)
                } catch {
                    html = Self.errorHTML(message: error.localizedDescription, isDark: isDark)
                }
                DispatchQueue.main.async {
                    // Keep the last good SVG when this render failed, so Copy
                    // SVG/PNG still works through a transient source error.
                    self?.lastSVGData = PlantUMLPreviewState.updatedCache(
                        current: self?.lastSVGData, rendered: svgData)
                    self?.lastRenderedDarkMode = isDark
                    web.loadHTMLString(html, baseURL: nil)
                }
            }
        }

        // MARK: - Interactive preview (entity → source)

        /// Intercept `mindo-src:<entity>` link clicks from the rendered diagram
        /// and jump the source editor to that entity's first occurrence. All
        /// other navigations (the initial loadHTMLString) are allowed.
        public func webView(_ webView: WKWebView,
                            decidePolicyFor navigationAction: WKNavigationAction,
                            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, url.scheme == "mindo-src" else {
                decisionHandler(.allow); return
            }
            decisionHandler(.cancel)
            let raw = String(url.absoluteString.dropFirst("mindo-src:".count))
            let entity = raw.removingPercentEncoding ?? raw
            jumpToEntity(entity)
        }

        private func jumpToEntity(_ entity: String) {
            guard let tv = textView,
                  let range = PlantUMLSource.firstRange(ofEntity: entity, in: tv.string) else { return }
            tv.scrollRangeToVisible(range)
            tv.setSelectedRange(range)
            tv.window?.makeFirstResponder(tv)
        }

        // MARK: - Clipboard

        /// Copy the most recently rendered diagram to NSPasteboard as SVG
        /// text. Mirrors what mindolph's PlantUmlEditor exposes via the
        /// preview's right-click menu.
        @objc public func copyDiagramAsSVG() {
            guard PlantUMLClipboard.outcome(for: lastSVGData) == .copied,
                  let data = lastSVGData, let svg = String(data: data, encoding: .utf8) else {
                reportNothingToCopy()
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(svg, forType: .string)
            flashFooter("Copied SVG to clipboard")
        }

        /// Rasterize the cached SVG to PNG via NSImage and put it on the
        /// pasteboard as an image. Caller can paste straight into Slack /
        /// Notes / etc.
        @objc public func copyDiagramAsPNG() {
            guard PlantUMLClipboard.outcome(for: lastSVGData) == .copied,
                  let data = lastSVGData, let image = NSImage(data: data) else {
                reportNothingToCopy()
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
            flashFooter("Copied PNG to clipboard")
        }

        /// Export the rendered diagram to an SVG or PNG file. The format is
        /// driven by the extension the user picks in the save panel (an
        /// accessory popup), defaulting to the source's base name. No-op with
        /// feedback when nothing has rendered yet.
        @objc public func exportDiagram() {
            guard PlantUMLClipboard.outcome(for: lastSVGData) == .copied else {
                reportNothingToCopy()
                return
            }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [
                UTType(filenameExtension: "svg") ?? .svg,
                UTType.png,
            ]
            // Format picker so the user can flip SVG ↔ PNG; keep the panel's
            // filename extension in sync.
            let formats = PlantUMLImageExport.Format.allCases
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 90, height: 24))
            popup.addItems(withTitles: formats.map { $0.fileExtension.uppercased() })
            popup.target = self
            popup.action = #selector(exportFormatChanged(_:))
            let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
            let label = NSTextField(labelWithString: "Format:")
            label.frame = NSRect(x: 8, y: 4, width: 60, height: 20)
            popup.frame = NSRect(x: 70, y: 2, width: 90, height: 24)
            accessory.addSubview(label)
            accessory.addSubview(popup)
            panel.accessoryView = accessory
            exportPanel = panel

            panel.nameFieldStringValue = PlantUMLImageExport.defaultFilename(
                sourceURL: parent.documentURL, format: formats.first ?? .svg)
            guard panel.runModal() == .OK, let url = panel.url else { exportPanel = nil; return }
            exportPanel = nil

            let format = PlantUMLImageExport.Format(rawValue: url.pathExtension.lowercased()) ?? .svg
            guard let data = PlantUMLImageExport.data(forSVG: lastSVGData, format: format) else {
                NSSound.beep()
                flashFooter("Export failed — couldn't encode the diagram")
                return
            }
            do {
                try data.write(to: url)
                flashFooter("Exported \(format.fileExtension.uppercased()) to \(url.lastPathComponent)")
            } catch {
                NSSound.beep()
                flashFooter("Export failed — \(error.localizedDescription)")
            }
        }

        /// Held only while the export panel is up so the format popup's
        /// action can retarget its filename extension.
        private var exportPanel: NSSavePanel?

        @objc private func exportFormatChanged(_ sender: NSPopUpButton) {
            guard let panel = exportPanel,
                  let format = PlantUMLImageExport.Format(rawValue: sender.titleOfSelectedItem?.lowercased() ?? "") else { return }
            // Swap the extension on the current filename stem.
            let stem = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = stem + "." + format.fileExtension
        }

        /// Copy the raw PlantUML source to the pasteboard — useful for
        /// sharing the script without exporting an image. Available even
        /// before a render (the source always exists).
        @objc public func copyScript() {
            let source = parent.text
            guard !source.isEmpty else {
                NSSound.beep()
                flashFooter("Nothing to copy — the script is empty")
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(source, forType: .string)
            flashFooter("Copied PlantUML script to clipboard")
        }

        /// No rendered diagram yet (or it failed) — beep and say so in the
        /// footer instead of the old silent no-op.
        private func reportNothingToCopy() {
            NSSound.beep()
            flashFooter("Nothing to copy — diagram hasn't rendered yet")
        }

        /// Briefly show `message` in the status footer, then restore the
        /// normal line/char stats after a couple seconds.
        private func flashFooter(_ message: String) {
            statusFooter?.stringValue = message
            statsDebouncer.schedule(after: 2.0) { [weak self] in self?.refreshStatusFooter() }
        }

        private static func previewHTML(svg: String, isDark: Bool) -> String {
            let bg = isDark ? "#1d1d1f" : "#fafafa"
            return """
            <!doctype html>
            <html><head><meta charset="utf-8"><style>
            html, body { height: 100%; margin: 0; background: \(bg); }
            body { display: flex; align-items: center; justify-content: center; padding: 16px; }
            svg { max-width: 100%; height: auto; }
            </style></head><body>\(svg)</body></html>
            """
        }

        private static func errorHTML(message: String, isDark: Bool) -> String {
            let bg = isDark ? "#1d1d1f" : "#fafafa"
            let fg = isDark ? "#e6e6e6" : "#222"
            let escaped = message
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return """
            <!doctype html>
            <html><head><meta charset="utf-8"><style>
            body { font: 13px ui-monospace, "SF Mono", Menlo, monospace;
                   white-space: pre-wrap; padding: 24px;
                   background: \(bg); color: \(fg); }
            </style></head><body>\(escaped)</body></html>
            """
        }
    }
}
