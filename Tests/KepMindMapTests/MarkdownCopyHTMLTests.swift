import XCTest
import AppKit
import KepCore
@testable import KepMarkdown

/// C2 — copy rendered markdown to the clipboard as HTML (Obsidian "Copy as
/// HTML"). Uses a private pasteboard so the user's clipboard isn't touched.
final class MarkdownCopyHTMLTests: XCTestCase {

    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("kep.test.\(UUID().uuidString)"))
    }

    func testCopyPutsHTMLAndStringFlavors() {
        let pb = scratchPasteboard()
        let html = MarkdownExporter.copyHTMLToPasteboard(markdown: "# Title\n\nHello **world**", pasteboard: pb)
        // Returned + pasteboard agree, and it's a real HTML document.
        XCTAssertTrue(html.contains("<h1"))
        XCTAssertEqual(pb.string(forType: .html), html, ".html flavor present for rich consumers")
        XCTAssertEqual(pb.string(forType: .string), html, ".string fallback carries the HTML source")
    }

    func testRenderedHTMLReflectsMarkdown() {
        let pb = scratchPasteboard()
        let html = MarkdownExporter.copyHTMLToPasteboard(markdown: "- one\n- two", pasteboard: pb)
        XCTAssertTrue(html.contains("<li"), "list markdown becomes <li> elements")
        XCTAssertTrue(html.contains("one") && html.contains("two"))
    }

    func testMarkdownPreviewMenuOffersCopyHTML() {
        let actions = PreviewContextMenu.markdown().map(\.action)
        XCTAssertTrue(actions.contains(.copyHTML), "markdown preview context menu exposes Copy as HTML")
        // And it's enabled (no render needed — the source is always available).
        let item = PreviewContextMenu.markdown().first { $0.action == .copyHTML }
        XCTAssertEqual(item?.isEnabled, true)
    }
}
