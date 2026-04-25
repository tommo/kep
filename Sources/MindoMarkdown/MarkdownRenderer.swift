import Foundation
import Markdown

/// Converts a Markdown document to standalone HTML using Apple's `swift-markdown`.
/// Wraps the result in a styled HTML document suitable for `WKWebView`.
public enum MarkdownRenderer {

    /// CSS used by the preview pane. Matches the readable-content tradition of the
    /// Mindolph Java app's WebView styling: comfortable line height, block code,
    /// quoted blocks, and table separators.
    public static let previewStylesheet = """
    :root { color-scheme: light dark; }
    body {
      font: 14px -apple-system, "SF Pro Text", system-ui, sans-serif;
      line-height: 1.55;
      max-width: 720px;
      margin: 24px auto;
      padding: 0 24px;
      color: #1a1a1a;
      background: #fafafa;
    }
    @media (prefers-color-scheme: dark) {
      body { color: #e6e6e6; background: #1d1d1f; }
      a { color: #6ab1ff; }
      code { background: #2b2b2e; }
      pre { background: #2b2b2e; }
      blockquote { border-left-color: #555; color: #ccc; }
      th, td { border-color: #444; }
    }
    h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin-top: 1.6em; }
    h1 { font-size: 1.8em; border-bottom: 1px solid #eee; padding-bottom: .25em; }
    h2 { font-size: 1.4em; border-bottom: 1px solid #eee; padding-bottom: .2em; }
    a { color: #0a66c2; }
    code {
      font: 12.5px ui-monospace, "SF Mono", Menlo, monospace;
      background: #f0f0f2;
      padding: 1px 4px;
      border-radius: 3px;
    }
    pre {
      background: #f0f0f2;
      padding: 12px 14px;
      border-radius: 6px;
      overflow-x: auto;
    }
    pre code { background: transparent; padding: 0; }
    blockquote {
      border-left: 3px solid #d0d0d4;
      color: #555;
      margin: 1em 0;
      padding: 0 1em;
    }
    table { border-collapse: collapse; margin: 1em 0; }
    th, td { border: 1px solid #d0d0d4; padding: 6px 10px; }
    img { max-width: 100%; }
    """

    /// Convert raw Markdown text to a complete HTML document string.
    public static func render(markdown: String) -> String {
        let document = Document(parsing: markdown, options: [.parseBlockDirectives])
        var formatter = HTMLFormatter()
        formatter.visit(document)
        let body = formatter.result
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>\(previewStylesheet)</style>
        </head><body>\(body)</body></html>
        """
    }

    /// Plain HTML body (no `<html>` wrapper), useful for embedding in larger templates.
    public static func renderBody(markdown: String) -> String {
        let document = Document(parsing: markdown, options: [.parseBlockDirectives])
        var formatter = HTMLFormatter()
        formatter.visit(document)
        return formatter.result
    }
}
