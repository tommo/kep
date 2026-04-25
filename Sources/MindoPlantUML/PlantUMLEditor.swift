import AppKit
import SwiftUI
import WebKit
import MindoBase

/// Split editor for `.puml` files: NSTextView source on the left, WKWebView
/// preview of the rendered SVG on the right. Renders by shelling out to the
/// PlantUML CLI/jar via `PlantUMLRenderer`.
public struct PlantUMLEditor: NSViewRepresentable {
    @Binding public var text: String
    public var isDarkMode: Bool

    public init(text: Binding<String>, isDarkMode: Bool = false) {
        self._text = text
        self.isDarkMode = isDarkMode
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let toolbar = makeToolbar(coordinator: context.coordinator)

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin

        let (scroll, textView) = CodeArea.makeMonospaced(text: text, delegate: context.coordinator)

        let web = WKWebView()
        web.setValue(false, forKey: "drawsBackground")

        split.addArrangedSubview(scroll)
        split.addArrangedSubview(web)
        split.setHoldingPriority(NSLayoutConstraint.Priority(rawValue: 250), forSubviewAt: 0)

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

        context.coordinator.textView = textView
        context.coordinator.webView = web
        context.coordinator.applyHighlighting()
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
        // Spacer between insert + copy clusters.
        let divider = NSBox(); divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stack.addArrangedSubview(divider)
        stack.addArrangedSubview(skeletonButton("Copy SVG", tooltip: "Copy rendered diagram as SVG", action: #selector(Coordinator.copyDiagramAsSVG)))
        stack.addArrangedSubview(skeletonButton("Copy PNG", tooltip: "Copy rendered diagram as PNG", action: #selector(Coordinator.copyDiagramAsPNG)))
        stack.addArrangedSubview(NSView())  // spacer
        return stack
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyHighlighting()
        if let tv = context.coordinator.textView, tv.string != text {
            tv.string = text
            context.coordinator.applyHighlighting()
            context.coordinator.scheduleRender(immediate: true)
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PlantUMLEditor
        var textView: NSTextView?
        var webView: WKWebView?
        let highlighter = PlantUMLHighlighter()
        private let renderDebouncer = Debouncer()
        /// Most recent successful SVG render. Cached so the toolbar's Copy
        /// SVG / Copy PNG buttons don't re-shell out to PlantUML each time.
        private var lastSVGData: Data?

        init(parent: PlantUMLEditor) { self.parent = parent }

        public func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            applyHighlighting()
            scheduleRender(immediate: false)
        }

        // MARK: - Toolbar actions

        @objc func insertSequence() { insertSkeleton(PlantUMLSkeletons.sequence) }
        @objc func insertClass()    { insertSkeleton(PlantUMLSkeletons.classDiagram) }
        @objc func insertActivity() { insertSkeleton(PlantUMLSkeletons.activity) }
        @objc func insertState()    { insertSkeleton(PlantUMLSkeletons.state) }
        @objc func insertUseCase()  { insertSkeleton(PlantUMLSkeletons.useCase) }
        @objc func insertMindMap()  { insertSkeleton(PlantUMLSkeletons.mindMap) }

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
                    self?.lastSVGData = svgData
                    web.loadHTMLString(html, baseURL: nil)
                }
            }
        }

        // MARK: - Clipboard

        /// Copy the most recently rendered diagram to NSPasteboard as SVG
        /// text. Mirrors what mindolph's PlantUmlEditor exposes via the
        /// preview's right-click menu.
        @objc public func copyDiagramAsSVG() {
            guard let data = lastSVGData, let svg = String(data: data, encoding: .utf8) else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(svg, forType: .string)
        }

        /// Rasterize the cached SVG to PNG via NSImage and put it on the
        /// pasteboard as an image. Caller can paste straight into Slack /
        /// Notes / etc.
        @objc public func copyDiagramAsPNG() {
            guard let data = lastSVGData, let image = NSImage(data: data) else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
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
