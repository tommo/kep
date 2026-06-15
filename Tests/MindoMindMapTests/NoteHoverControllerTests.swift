import XCTest
import AppKit
@testable import MindoMindMap

/// The note hover popover was showing up empty. These guard that the controller
/// actually renders the note text and sizes itself to non-zero — i.e. the
/// markdown → attributed-string → label pipeline produces visible content.
@MainActor
final class NoteHoverControllerTests: XCTestCase {

    private func label(in view: NSView) -> NSTextField? {
        if let tf = view as? NSTextField { return tf }
        for sub in view.subviews { if let hit = label(in: sub) { return hit } }
        return nil
    }

    func testRendersNonEmptyContentAndSize() {
        let vc = NoteHoverController(markdown: "Remember **this** and `that`.")
        vc.loadViewIfNeeded()

        XCTAssertGreaterThan(vc.preferredContentSize.width, 0, "popover has a width")
        XCTAssertGreaterThan(vc.preferredContentSize.height, 0, "popover has a height")

        let tf = label(in: vc.view)
        XCTAssertNotNil(tf, "a text label was added")
        XCTAssertGreaterThan(tf?.attributedStringValue.length ?? 0, 0,
                             "the label actually carries the rendered note text")
        XCTAssertTrue(tf?.attributedStringValue.string.contains("Remember") ?? false,
                      "the note text survives markdown rendering")
    }

    func testPlainTextFallbackStillRenders() {
        let vc = NoteHoverController(markdown: "just plain text")
        vc.loadViewIfNeeded()
        let tf = label(in: vc.view)
        XCTAssertEqual(tf?.attributedStringValue.string.contains("plain text"), true)
        XCTAssertGreaterThan(vc.preferredContentSize.height, 0)
    }
}
