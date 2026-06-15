import SwiftUI
import WebKit
import MindoMarkdown

/// Renders a node's markdown content as HTML in the inspector. A lightweight,
/// read-only WKWebView reusing the same MarkdownRenderer the markdown editor's
/// preview uses, so node content looks identical to a markdown document.
struct MarkdownContentPreview: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.setValue(false, forKey: "drawsBackground")   // blend with the inspector
        load(into: web)
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        if context.coordinator.lastMarkdown != markdown {
            context.coordinator.lastMarkdown = markdown
            load(into: web)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(markdown: markdown) }

    private func load(into web: WKWebView) {
        web.loadHTMLString(MarkdownRenderer.render(markdown: markdown), baseURL: nil)
    }

    final class Coordinator {
        var lastMarkdown: String
        init(markdown: String) { lastMarkdown = markdown }
    }
}
