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

    public func makeNSView(context: Context) -> NSSplitView {
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin

        let (scroll, textView) = CodeArea.makeMonospaced(text: text, delegate: context.coordinator)

        let web = WKWebView()
        web.setValue(false, forKey: "drawsBackground")

        split.addArrangedSubview(scroll)
        split.addArrangedSubview(web)
        split.setHoldingPriority(NSLayoutConstraint.Priority(rawValue: 250), forSubviewAt: 0)

        context.coordinator.textView = textView
        context.coordinator.webView = web
        context.coordinator.applyHighlighting()
        context.coordinator.scheduleRender(immediate: true)
        return split
    }

    public func updateNSView(_ nsView: NSSplitView, context: Context) {
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

        init(parent: PlantUMLEditor) { self.parent = parent }

        public func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            applyHighlighting()
            scheduleRender(immediate: false)
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
            DispatchQueue.global(qos: .userInitiated).async {
                let html: String
                do {
                    let svg = try PlantUMLRenderer.shared.renderSVG(source: source)
                    html = Self.previewHTML(svg: String(data: svg, encoding: .utf8) ?? "", isDark: isDark)
                } catch let err as PlantUMLRenderer.RenderError {
                    html = Self.errorHTML(message: err.errorDescription ?? "Unknown error", isDark: isDark)
                } catch {
                    html = Self.errorHTML(message: error.localizedDescription, isDark: isDark)
                }
                DispatchQueue.main.async { web.loadHTMLString(html, baseURL: nil) }
            }
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
