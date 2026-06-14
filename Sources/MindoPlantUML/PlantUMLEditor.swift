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
        let toolbar = makeToolbar(coordinator: context.coordinator)

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

        toolbar.translatesAutoresizingMaskIntoConstraints = false
        split.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toolbar)
        container.addSubview(split)
        container.addSubview(footer)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: container.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 32),
            split.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            split.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            footer.heightAnchor.constraint(equalToConstant: 16),
        ])

        context.coordinator.textView = textView
        context.coordinator.webView = web
        context.coordinator.statusFooter = footer
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

        func skeletonButton(_ title: String, tooltip: String, action: Selector) -> NSButton {
            let b = NSButton(title: title, target: coordinator, action: action)
            b.bezelStyle = .accessoryBarAction
            b.toolTip = tooltip
            return b
        }
        stack.addArrangedSubview(skeletonButton("Sequence", tooltip: "Insert sequence diagram skeleton", action: #selector(Coordinator.insertSequence)))
        stack.addArrangedSubview(skeletonButton("Class",    tooltip: "Insert class diagram skeleton",   action: #selector(Coordinator.insertClass)))
        stack.addArrangedSubview(skeletonButton("Activity", tooltip: "Insert activity diagram skeleton", action: #selector(Coordinator.insertActivity)))
        stack.addArrangedSubview(skeletonButton("State",    tooltip: "Insert state diagram skeleton",   action: #selector(Coordinator.insertState)))
        stack.addArrangedSubview(skeletonButton("Use Case", tooltip: "Insert use case diagram skeleton", action: #selector(Coordinator.insertUseCase)))
        stack.addArrangedSubview(skeletonButton("Mind Map", tooltip: "Insert mind map skeleton",        action: #selector(Coordinator.insertMindMap)))
        let commentDivider = NSBox(); commentDivider.boxType = .separator
        commentDivider.translatesAutoresizingMaskIntoConstraints = false
        commentDivider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        commentDivider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stack.addArrangedSubview(commentDivider)
        stack.addArrangedSubview(skeletonButton("Comment",  tooltip: "Toggle line comment (⌘/)",       action: #selector(Coordinator.toggleLineComment)))
        stack.addArrangedSubview(skeletonButton("Block",    tooltip: "Insert block comment /' '/",    action: #selector(Coordinator.insertBlockComment)))
        // Spacer between insert + copy clusters.
        let divider = NSBox(); divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stack.addArrangedSubview(divider)
        stack.addArrangedSubview(skeletonButton("Copy SVG", tooltip: "Copy rendered diagram as SVG", action: #selector(Coordinator.copyDiagramAsSVG)))
        stack.addArrangedSubview(skeletonButton("Copy PNG", tooltip: "Copy rendered diagram as PNG", action: #selector(Coordinator.copyDiagramAsPNG)))
        stack.addArrangedSubview(skeletonButton("Export…", tooltip: "Export rendered diagram to an SVG or PNG file", action: #selector(Coordinator.exportDiagram)))
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
    }

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlantUMLEditor
        var textView: NSTextView?
        var webView: WKWebView?
        weak var statusFooter: NSTextField?
        let highlighter = PlantUMLHighlighter()
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
            case .export:     exportDiagram()
            case .viewSource: textView?.window?.makeFirstResponder(textView)
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

        /// Recompute the line / char status footer for the current source.
        /// Lines are split on \n (one entry per visible line including blanks);
        /// chars are grapheme clusters so emoji + combining marks count once.
        func refreshStatusFooter() {
            guard let footer = statusFooter, let body = textView?.string else { return }
            let lines = body.split(separator: "\n", omittingEmptySubsequences: false).count
            footer.stringValue = "\(lines) lines · \(body.count) chars"
        }

        // MARK: - Toolbar actions

        @objc func insertSequence() { insertSkeleton(PlantUMLSkeletons.sequence) }
        @objc func insertClass()    { insertSkeleton(PlantUMLSkeletons.classDiagram) }
        @objc func insertActivity() { insertSkeleton(PlantUMLSkeletons.activity) }
        @objc func insertState()    { insertSkeleton(PlantUMLSkeletons.state) }
        @objc func insertUseCase()  { insertSkeleton(PlantUMLSkeletons.useCase) }
        @objc func insertMindMap()  { insertSkeleton(PlantUMLSkeletons.mindMap) }

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
            let source = parent.text
            let isDark = parent.isDarkMode
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let html: String
                var svgData: Data? = nil
                do {
                    let svg = try PlantUMLRenderer.shared.renderSVG(source: source)
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
