import Foundation
import Markdown
import MindoCore

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

    /// CSS overriding the body (sans) and code (mono) font families, appended
    /// after the base stylesheet so the cascade picks the user's choice. Pure
    /// (no PrefKeys) so the sanitization + emitted rules are unit-testable.
    /// Empty when neither font is set. Names are stripped of characters that
    /// could break out of the CSS string.
    public static func fontOverrideCSS(sans: String?, mono: String?) -> String {
        var rules: [String] = []
        if let s = sanitizedFontName(sans) {
            rules.append("body { font-family: \"\(s)\", -apple-system, system-ui, sans-serif; }")
        }
        if let m = sanitizedFontName(mono) {
            rules.append("code, pre, pre code { font-family: \"\(m)\", ui-monospace, Menlo, monospace; }")
        }
        return rules.joined(separator: "\n")
    }

    static func sanitizedFontName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        let cleaned = trimmed.filter { $0 != "\"" && $0 != ";" && $0 != "\n" && $0 != "{" && $0 != "}" }
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Convert raw Markdown text to a complete HTML document string. Applies
    /// the user's preview font overrides (PrefKeys) so the preview and the
    /// HTML/PDF exporters — which both call this — match.
    public static func render(markdown: String) -> String {
        let document = Document(parsing: WikiLinkMarkdown.linkify(markdown), options: [.parseBlockDirectives])
        var formatter = HTMLFormatter()
        formatter.visit(document)
        let body = formatter.result
        let fontCSS = fontOverrideCSS(
            sans: PrefKeys.string(PrefKeys.markdownPreviewFont),
            mono: PrefKeys.string(PrefKeys.markdownPreviewMonoFont))
        return """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <style>\(previewStylesheet)\n\(fontCSS)</style>
        <script>\(scrollSyncScript)</script>
        </head><body>\(body)</body></html>
        """
    }

    /// JavaScript shim injected into every preview document. It exposes:
    ///   window.mindoScrollTo(fraction) — scrolls the page to the given
    ///                                    fractional position (0…1).
    /// And reports user-driven scrolls back to the host via the
    /// `previewScroll` message handler.
    public static let scrollSyncScript = """
    (function() {
        let suppress = false;
        window.mindoScrollTo = function(fraction) {
            const max = Math.max(0, document.documentElement.scrollHeight - window.innerHeight);
            suppress = true;
            window.scrollTo(0, fraction * max);
            // Re-enable native scroll reporting on the next tick.
            requestAnimationFrame(() => { suppress = false; });
        };
        window.addEventListener('scroll', function() {
            if (suppress) return;
            const max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
            const fraction = window.scrollY / max;
            try {
                window.webkit.messageHandlers.previewScroll.postMessage(fraction);
            } catch (e) { /* host handler not present */ }
        }, { passive: true });
        // Anchor-link click → post slug to host so the editor can scroll
        // the code area to the matching heading line. Mirrors mindolph's
        // HTMLAnchorElement listener.
        document.addEventListener('click', function(ev) {
            let el = ev.target;
            while (el && el.tagName !== 'A') el = el.parentElement;
            if (!el) return;
            const href = el.getAttribute('href') || '';
            if (!href.startsWith('#')) return;
            ev.preventDefault();
            try {
                window.webkit.messageHandlers.previewAnchor.postMessage(href.slice(1));
            } catch (e) { /* host handler not present */ }
        }, false);
    })();
    """

    /// Slugify a heading title the same way GitHub's "anchorize" does:
    /// lowercase, strip non-alphanumerics-and-spaces-and-dashes, collapse
    /// whitespace runs to single dashes. Keeps the slug stable across
    /// renderer changes and matches what the WKWebView's <a href="#…">
    /// links produce when generated by HTMLFormatter.
    public static func slugify(_ heading: String) -> String {
        var out = ""
        var lastWasDash = false
        for ch in heading.lowercased() {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasDash = false
            } else if ch.isWhitespace || ch == "-" || ch == "_" {
                if !lastWasDash && !out.isEmpty {
                    out.append("-")
                    lastWasDash = true
                }
            }
            // Punctuation drops silently.
        }
        // Trim trailing dash, if any.
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    /// Plain HTML body (no `<html>` wrapper), useful for embedding in larger templates.
    public static func renderBody(markdown: String) -> String {
        let document = Document(parsing: WikiLinkMarkdown.linkify(markdown), options: [.parseBlockDirectives])
        var formatter = HTMLFormatter()
        formatter.visit(document)
        return formatter.result
    }
}
