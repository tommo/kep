import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// The clickable collapsator: a parent topic shows a fold circle on the side
/// facing its children, and clicking it toggles collapse — mouse-driven
/// folding without the context menu (XMind / mindolph parity). Driven through
/// real mouse events at the indicator's own hit rect.
@MainActor
final class MindMapInteractiveCollapseTests: XCTestCase {

    /// Root ─ A(A1, A2) ─ B(leaf), A & B on the right.
    private func build() throws -> (WindowedMindMap, Topic, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A"); a.setAttribute(TopicAttribute.leftSide, "false")
        a.addChild(text: "A1"); a.addChild(text: "A2")
        let b = root.addChild(text: "B"); b.setAttribute(TopicAttribute.leftSide, "false")
        let h = WindowedMindMap(map: map)
        return (h, root, a, b)
    }

    /// Click the centre of `topic`'s collapsator circle. Re-fetches the rect
    /// each call since a fold relayout can move the node.
    @discardableResult
    private func clickIndicator(_ h: WindowedMindMap, _ topic: Topic) -> Bool {
        guard let rect = h.view.element(forTopic: topic)?.collapseIndicatorRect else { return false }
        h.click(viewPoint: CGPoint(x: rect.midX, y: rect.midY))
        return true
    }

    func testClickingIndicatorTogglesCollapse() throws {
        let (h, _, a, _) = try build()
        XCTAssertFalse(a.attribute(TopicAttribute.collapsed).flatMap(Bool.init) ?? false)

        XCTAssertTrue(clickIndicator(h, a), "A (a parent) shows a collapsator")
        XCTAssertEqual(a.attribute(TopicAttribute.collapsed), "true", "first click folds A")

        XCTAssertTrue(clickIndicator(h, a), "the collapsator is still there when folded (shows +)")
        XCTAssertNil(a.attribute(TopicAttribute.collapsed), "second click unfolds A")
    }

    func testLeafAndRootHaveNoIndicator() throws {
        let (h, root, _, b) = try build()
        XCTAssertNil(h.view.element(forTopic: b)?.collapseIndicatorRect, "a leaf has no collapsator")
        XCTAssertNil(h.view.element(forTopic: root)?.collapseIndicatorRect, "the root has no collapsator")
        // Clicking where B's (absent) indicator would be must not fold anything.
        XCTAssertFalse(clickIndicator(h, b))
        XCTAssertNil(b.attribute(TopicAttribute.collapsed))
    }

    func testCollapsatorToggleIsUndoable() throws {
        let (h, _, a, _) = try build()
        let mgr = UndoManager(); mgr.groupsByEvent = false
        h.view.injectedUndoManager = mgr

        clickIndicator(h, a)
        XCTAssertEqual(a.attribute(TopicAttribute.collapsed), "true", "folded")
        mgr.undo()
        XCTAssertNil(a.attribute(TopicAttribute.collapsed), "undo unfolds A")
        mgr.redo()
        XCTAssertEqual(a.attribute(TopicAttribute.collapsed), "true", "redo re-folds A")
    }

    /// The indicator sits on the outward side — right edge for a right-side
    /// node — so it never overlaps the node's own text box.
    func testIndicatorSitsOutsideTheNodeFrame() throws {
        let (h, _, a, _) = try build()
        let el = h.view.element(forTopic: a)!
        let rect = el.collapseIndicatorRect!
        XCTAssertGreaterThanOrEqual(rect.minX, el.frame.maxX, "right-side collapsator is right of the box")
        XCTAssertEqual(rect.midY, el.frame.midY, accuracy: 0.5, "vertically centred on the node")
    }
}
