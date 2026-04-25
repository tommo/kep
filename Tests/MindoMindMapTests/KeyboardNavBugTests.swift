import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

@MainActor
final class KeyboardNavBugTests: XCTestCase {

    /// Regression for kanban bug #36: arrow keys did nothing on a freshly
    /// opened mindmap because (a) selectedElement was nil and every move()
    /// guard fell through, and (b) first responder lived on the sidebar
    /// list. The display(map:) call now auto-selects the root and async
    /// requests focus.
    func testDisplayAutoSelectsRoot() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        _ = root.addChild(text: "A")

        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        XCTAssertNil(view.selectedElement)
        view.display(map: map)
        XCTAssertNotNil(view.selectedElement, "display(map:) should auto-select root")
        XCTAssertTrue(view.selectedElement?.topic === root)
    }

    /// With a selected root and a child, hitting "right arrow" via the
    /// public element-resolver path should land on the child, even with no
    /// click first.
    func testRightArrowFromAutoSelectedRootMovesToFirstChild() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")

        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.display(map: map)
        guard let primary = view.selectedElement else {
            XCTFail("auto-selection failed"); return
        }
        let next = view.element(in: .right, of: primary)
        XCTAssertTrue(next?.topic === a)
    }

    /// performKeyEquivalent should swallow Tab/arrows when we're first
    /// responder so the window's focus loop doesn't grab them. We can't
    /// install a real window here, so just sanity-check the override returns
    /// the system fallback when we're NOT first responder.
    func testPerformKeyEquivalentDoesNotCrashOutsideAWindow() {
        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        let ev = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\t", charactersIgnoringModifiers: "\t",
            isARepeat: false, keyCode: 48
        )!
        // No window → we're not the first responder; should fall through.
        XCTAssertFalse(view.performKeyEquivalent(with: ev))
    }
}
