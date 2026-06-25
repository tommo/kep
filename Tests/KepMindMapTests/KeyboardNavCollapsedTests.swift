import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// Navigation must never move the selection INTO a collapsed node's hidden
/// children — that would put the highlight on an invisible topic (a "my
/// selection disappeared" instability).
@MainActor
final class KeyboardNavCollapsedTests: XCTestCase {

    private func collapsedFixture() -> (MindMapView, Topic, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let a = root.addChild(text: "A")          // right side (index 0)
        let a1 = a.addChild(text: "A1")
        _ = a.addChild(text: "A2")
        a.setAttribute(TopicAttribute.collapsed, "true")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        return (view, a, a1, root)
    }

    private func nav(_ v: MindMapView, _ t: Topic, _ d: MindMapView.Direction) -> Topic? {
        guard let el = v.element(forTopic: t) else { return nil }
        return v.element(in: d, of: el)?.topic
    }

    func testRightIntoCollapsedNodeDoesNotSelectHiddenChild() {
        let (view, a, _, _) = collapsedFixture()
        // A is right-side and collapsed → Right (inward) must NOT enter it.
        XCTAssertNil(nav(view, a, .right), "must not navigate into a collapsed node's hidden children")
    }

    func testLeftStillReachesParentFromCollapsedNode() {
        let (view, a, _, root) = collapsedFixture()
        // Outward (Left for a right-side node) still works.
        XCTAssertTrue(nav(view, a, .left) === root)
    }

    func testExpandedNodeStillNavigatesIntoChildren() {
        let (view, a, a1, _) = collapsedFixture()
        a.setAttribute(TopicAttribute.collapsed, nil)   // expand
        view.rebuildElementsPublic()
        XCTAssertTrue(nav(view, a, .right) === a1, "an expanded node still navigates inward")
    }

    func testLeftSideCollapsedNodeAlsoGuarded() {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        // Force a left-side collapsed node.
        let l = root.addChild(text: "L"); l.setAttribute(TopicAttribute.leftSide, "true")
        _ = l.addChild(text: "L1")
        l.setAttribute(TopicAttribute.collapsed, "true")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        guard let el = view.element(forTopic: l) else { return XCTFail("no element") }
        // Left is inward on the left side → must not enter the collapsed node.
        XCTAssertNil(view.element(in: .left, of: el))
        XCTAssertTrue(view.element(in: .right, of: el)?.topic === root, "Right still reaches root")
    }
}
