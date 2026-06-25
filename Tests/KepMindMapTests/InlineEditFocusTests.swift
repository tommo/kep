import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// Regression: pressing Enter on a node creates a new node in edit mode, but a
/// SwiftUI re-render's `grabFocus()` (updateNSView, next runloop) yanked first
/// responder back to the canvas, so the new node couldn't be typed into. Uses
/// the real windowed harness so the field editor is live.
@MainActor
final class InlineEditFocusTests: XCTestCase {

    private func make() -> (WindowedMindMap, root: Topic, child: Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let child = root.addChild(text: "A")
        let h = WindowedMindMap(map: map, size: NSSize(width: 900, height: 640))
        return (h, root, child)
    }

    func testGrabFocusDoesNotStealFromOpenInlineEditor() throws {
        let (h, _, child) = make()
        let el = try XCTUnwrap(h.view.element(forTopic: child))
        h.view.selectElement(el)
        h.view.beginInlineEdit(on: el)
        try XCTSkipIf(h.view.inlineEditor?.currentEditor() == nil,
                      "headless host can't host a field editor")

        // Simulate the SwiftUI re-render focus grab that fires after the edit opens.
        h.view.grabFocus()

        XCTAssertNotNil(h.view.inlineEditor, "editor still open")
        XCTAssertFalse(h.window.firstResponder === h.view,
                       "grabFocus must NOT steal first responder from the inline editor")
        // The field editor is still live and typing reaches it.
        XCTAssertNotNil(h.view.inlineEditor?.currentEditor(),
                        "the inline editor keeps its field editor (still typeable)")
    }

    func testEnterCreatesSiblingThatStaysEditable() throws {
        let (h, root, child) = make()
        h.view.selectElement(h.view.element(forTopic: child))
        // Enter → add next sibling + begin editing it (the real flow).
        h.view.addNextSibling()
        try XCTSkipIf(h.view.inlineEditor?.currentEditor() == nil,
                      "headless host can't host a field editor")
        XCTAssertEqual(root.children.count, 2, "a sibling was created")

        // The post-mutation re-render grab must not break the new node's edit.
        h.view.grabFocus()
        XCTAssertNotNil(h.view.inlineEditor?.currentEditor(),
                        "new sibling stays in an editable (focused) state")
        XCTAssertFalse(h.window.firstResponder === h.view)
    }
}
