import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// The fold/unfold shortcut (XMind's `⌘/`) must never collapse the root —
/// folding it would hide the whole map. Non-root parents fold as usual.
@MainActor
final class CollapseRootGuardTests: XCTestCase {

    private func make() -> (MindMapView, root: Topic, child: Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let child = root.addChild(text: "A")
        _ = child.addChild(text: "A1")   // child has children so it's foldable
        let view = makeHeadlessMindMap(map: map)
        return (view, root, child)
    }

    func testFoldingRootIsNoOp() {
        let (view, root, _) = make()
        view.selectElement(view.element(forTopic: root))
        view.toggleCollapse(toCollapsed: true)
        XCTAssertNil(root.attribute(TopicAttribute.collapsed),
                     "root must not get a collapsed flag")
    }

    func testFoldingNonRootWorks() {
        let (view, _, child) = make()
        view.selectElement(view.element(forTopic: child))
        view.toggleCollapse(toCollapsed: true)
        XCTAssertEqual(child.attribute(TopicAttribute.collapsed), "true")
        view.toggleCollapse(toCollapsed: false)
        XCTAssertNil(child.attribute(TopicAttribute.collapsed), "unfold clears the flag")
    }

    /// ⌘/ toggle flips the selected topic's fold state.
    func testToggleCollapseSelectedFlips() {
        let (view, _, child) = make()
        view.selectElement(view.element(forTopic: child))
        view.toggleCollapseSelected()
        XCTAssertEqual(child.attribute(TopicAttribute.collapsed), "true")
        view.toggleCollapseSelected()
        XCTAssertNil(child.attribute(TopicAttribute.collapsed))
    }

    /// Arrow INTO a collapsed node auto-expands it and lands on a child.
    func testArrowIntoCollapsedNodeAutoExpands() {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A")
        a.setAttribute(TopicAttribute.leftSide, "false")   // right side
        let a1 = a.addChild(text: "A1")
        a.setAttribute(TopicAttribute.collapsed, "true")   // folded
        let view = makeHeadlessMindMap(map: map)
        view.selectElement(view.element(forTopic: a))

        view.move(.right)   // inward on a right-side node

        XCTAssertNil(a.attribute(TopicAttribute.collapsed), "A auto-expanded")
        XCTAssertTrue(view.selectedElement?.topic === a1, "selection stepped onto the first child")
    }
}
