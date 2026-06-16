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

        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        guard let primary = view.selectedElement else {
            XCTFail("auto-selection failed"); return
        }
        let next = view.element(in: .right, of: primary)
        XCTAssertTrue(next?.topic === a)
    }

    /// Navigating INTO a branch should land on the child nearest the source
    /// node's vertical position, NOT the first child by index. A parent with
    /// several children sits (vertically) opposite the middle of the block, so
    /// arrowing in should select the middle child.
    func testInwardNavigationUsesPositionNotIndex() {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let p = root.addChild(text: "P")
        p.setAttribute(TopicAttribute.leftSide, "false")   // right side
        let c0 = p.addChild(text: "C0")
        let c1 = p.addChild(text: "C1")
        let c2 = p.addChild(text: "C2")

        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let pEl = view.element(forTopic: p)!

        let next = view.element(in: .right, of: pEl)

        // The geometric nearest child to P's centre.
        let y = pEl.frame.midY
        let nearest = pEl.visibleChildren.min { abs($0.frame.midY - y) < abs($1.frame.midY - y) }
        XCTAssertTrue(next === nearest, "inward navigation picks the vertically nearest child")
        XCTAssertTrue(next?.topic === c1, "for a centred parent that's the middle child")
        XCTAssertFalse(next?.topic === c0, "not just the first child by index")
        _ = c2
    }

    /// When two children are equidistant from the parent's vertical centre,
    /// inward navigation prefers the UPPER one (smaller y on the flipped canvas).
    func testInwardNavigationTieBreaksToUpperChild() {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let p = root.addChild(text: "P")
        p.setAttribute(TopicAttribute.leftSide, "false")
        let top = p.addChild(text: "Top")
        let bottom = p.addChild(text: "Bottom")

        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let pEl = view.element(forTopic: p)!
        let topEl = view.element(forTopic: top)!, bottomEl = view.element(forTopic: bottom)!

        // Two children → parent centred between them → equidistant.
        let dTop = abs(topEl.frame.midY - pEl.frame.midY)
        let dBottom = abs(bottomEl.frame.midY - pEl.frame.midY)
        XCTAssertEqual(dTop, dBottom, accuracy: 0.5, "the two children are equidistant")
        XCTAssertLessThan(topEl.frame.midY, bottomEl.frame.midY, "Top is the upper node (flipped canvas)")

        let next = view.element(in: .right, of: pEl)
        XCTAssertTrue(next?.topic === top, "tie resolves to the upper child")
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
