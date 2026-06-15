import AppKit
import WebKit
import MindoMarkdown

/// Content for the note hover popover: the node's note is Markdown, so render
/// it the SAME way the markdown editor's preview does — `MarkdownRenderer`
/// (swift-markdown → styled HTML) in a WKWebView. That means headings, lists,
/// quotes, code blocks etc. render properly instead of showing raw `#`/`-`
/// markers. The popover starts at a sensible size and shrinks/grows to the
/// rendered content height once the web view finishes loading.
final class NoteHoverController: NSViewController {
    private let markdown: String
    private static let width: CGFloat = 360
    private static let initialHeight: CGFloat = 140

    init(markdown: String) {
        self.markdown = markdown
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The HTML the popover renders — extracted so it's unit-testable without a
    /// live web view (verifies the note really goes through Markdown rendering).
    static func html(for markdown: String) -> String {
        MarkdownRenderer.render(markdown: markdown)
    }

    override func loadView() {
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.initialHeight))
        web.setValue(false, forKey: "drawsBackground")   // transparent → popover chrome shows
        web.navigationDelegate = self
        web.loadHTMLString(Self.html(for: markdown), baseURL: nil)
        view = web
        preferredContentSize = NSSize(width: Self.width, height: Self.initialHeight)
    }
}

extension NoteHoverController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Resize the popover to hug the rendered content (clamped so a huge note
        // scrolls rather than filling the screen).
        webView.evaluateJavaScript("document.body.scrollHeight") { [weak self] result, _ in
            guard let self else { return }
            let measured: CGFloat
            if let d = result as? Double { measured = CGFloat(d) }
            else if let n = result as? CGFloat { measured = n }
            else { measured = Self.initialHeight }
            let clamped = min(max(measured + 8, 36), 440)
            self.preferredContentSize = NSSize(width: Self.width, height: clamped)
        }
    }
}
