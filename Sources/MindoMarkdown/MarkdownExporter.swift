import Foundation
import WebKit
import AppKit

/// Exports Markdown documents to disk in a couple of static formats.
///
/// - `exportHTML(...)` is purely synchronous and just writes the styled HTML
///   document produced by `MarkdownRenderer.render(...)`.
/// - `exportPDF(...)` round-trips the same HTML through an offscreen
///   `WKWebView` and uses `createPDF(configuration:)` (macOS 14+) to capture
///   the rendered preview as a PDF document.
public enum MarkdownExporter {

    public enum ExportError: Error, LocalizedError {
        case writeFailed(String)
        case renderFailed(String)

        public var errorDescription: String? {
            switch self {
            case .writeFailed(let s): return "Export write failed: \(s)"
            case .renderFailed(let s): return "PDF render failed: \(s)"
            }
        }
    }

    /// Convert `markdown` to a standalone styled HTML document and write it to
    /// `url`. Mirrors what's shown in the live preview.
    public static func exportHTML(markdown: String, to url: URL) throws {
        let html = MarkdownRenderer.render(markdown: markdown)
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
    }

    /// Render `markdown` to PDF using an offscreen `WKWebView`. The view loads
    /// the HTML, waits for `didFinish`, then captures `createPDF` output. The
    /// PDF data is written to `url`. Must be called on the main actor.
    @MainActor
    public static func exportPDF(markdown: String, to url: URL) async throws {
        let html = MarkdownRenderer.render(markdown: markdown)
        let bridge = OffscreenRenderBridge()
        try await bridge.renderPDF(html: html, to: url)
    }
}

/// Holds an offscreen `WKWebView` that loads HTML and emits PDF data once
/// page load completes. Kept in its own class so the navigation delegate's
/// callbacks can resume the awaiting continuation cleanly.
@MainActor
private final class OffscreenRenderBridge: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?
    private var destinationURL: URL?

    func renderPDF(html: String, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            self.destinationURL = url

            let config = WKWebViewConfiguration()
            // 8.5 x 11 inches at 96 DPI ≈ 816 x 1056 pt. Generous height so
            // long documents render in a single PDF page (createPDF auto-paginates
            // when the rect is the page rect; we use the default).
            let frame = NSRect(x: 0, y: 0, width: 816, height: 1056)
            let view = WKWebView(frame: frame, configuration: config)
            view.navigationDelegate = self
            self.webView = view
            view.loadHTMLString(html, baseURL: nil)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            guard let url = self.destinationURL else { return }
            let cfg = WKPDFConfiguration()
            do {
                let data = try await webView.pdf(configuration: cfg)
                try data.write(to: url, options: .atomic)
                self.continuation?.resume()
            } catch {
                self.continuation?.resume(throwing: MarkdownExporter.ExportError.renderFailed(error.localizedDescription))
            }
            self.continuation = nil
            self.destinationURL = nil
            self.webView = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: MarkdownExporter.ExportError.renderFailed(error.localizedDescription))
            self.continuation = nil
            self.webView = nil
        }
    }
}
