import XCTest
import AppKit
import WebKit
@testable import KepMindMap

/// The note hover popover renders the note as Markdown (it IS markdown), the
/// same pipeline the editor preview uses — so block elements like headings and
/// lists render instead of showing raw `#`/`-` markers.
@MainActor
final class NoteHoverControllerTests: XCTestCase {

    func testHeadingIsRenderedNotRaw() {
        let html = NoteHoverController.html(for: "# Title\n\nbody")
        XCTAssertFalse(html.contains("# Title"), "the raw markdown marker is gone")
        XCTAssertTrue(html.contains("Title"), "the heading text survives")
        XCTAssertTrue(html.localizedCaseInsensitiveContains("<h1"), "rendered as an <h1>")
    }

    func testListIsRendered() {
        let html = NoteHoverController.html(for: "- one\n- two")
        XCTAssertTrue(html.localizedCaseInsensitiveContains("<li"), "bullets render as list items")
        XCTAssertTrue(html.contains("one") && html.contains("two"))
    }

    func testInlineEmphasisRendered() {
        let html = NoteHoverController.html(for: "remember **this**")
        XCTAssertTrue(html.localizedCaseInsensitiveContains("<strong"), "bold renders")
    }

    func testControllerLoadsWebViewWithInitialSize() {
        let vc = NoteHoverController(markdown: "# hi")
        vc.loadViewIfNeeded()
        XCTAssertTrue(vc.view is WKWebView, "popover hosts a web view")
        XCTAssertGreaterThan(vc.preferredContentSize.width, 0)
        XCTAssertGreaterThan(vc.preferredContentSize.height, 0)
    }
}
