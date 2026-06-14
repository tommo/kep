import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Layout-stability coverage for the root-anchor introduced to stop the canvas
/// teleporting on edits. Exercises paths the round-trip test didn't: left-side
/// branches (mirror geometry), collapse/expand, and — through a real
/// NSScrollView — the top-left clamp + scroll-compensation that keeps the root
/// fixed in the VIEWPORT when a branch grows past the canvas edge.
@MainActor
final class MindMapLayoutAnchorTests: XCTestCase {

    private func bigView(_ map: MindMap) -> MindMapView {
        makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 1600, height: 1100))
    }

    private func rootCenter(_ v: MindMapView, _ root: Topic) -> CGPoint {
        let f = v.element(forTopic: root)!.frame
        return CGPoint(x: f.midX, y: f.midY)
    }

    /// Deleting inside a left-side branch (content shrinks, stays clear of the
    /// clamp) must not drift the root.
    func testLeftSideDeleteKeepsRootAnchored() {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let left = root.addChild(text: "Left"); left.setAttribute(TopicAttribute.leftSide, "true")
        let l1 = left.addChild(text: "L1"); left.addChild(text: "L2"); left.addChild(text: "L3")
        l1.addChild(text: "L1a"); l1.addChild(text: "L1b")
        root.addChild(text: "Right").setAttribute(TopicAttribute.leftSide, "false")
        let v = bigView(map)

        let before = rootCenter(v, root)
        v.selectElement(v.element(forTopic: l1))
        v.deleteSelection()
        let after = rootCenter(v, root)
        XCTAssertEqual(before.x, after.x, accuracy: 0.5, "root x stable when a left branch shrinks")
        XCTAssertEqual(before.y, after.y, accuracy: 0.5, "root y stable when a left branch shrinks")
    }

    /// Collapsing a heavy subtree removes a lot of content; expanding restores
    /// it. The root stays put through both.
    func testCollapseExpandKeepsRootAnchored() {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A"); a.setAttribute(TopicAttribute.leftSide, "false")
        for i in 0..<6 { a.addChild(text: "A\(i)") }
        root.addChild(text: "B").setAttribute(TopicAttribute.leftSide, "false")
        let v = bigView(map)

        let before = rootCenter(v, root)
        v.selectElement(v.element(forTopic: a))
        v.toggleCollapse(toCollapsed: true)
        XCTAssertEqual(a.attribute(TopicAttribute.collapsed), "true")
        var after = rootCenter(v, root)
        XCTAssertEqual(before.x, after.x, accuracy: 0.5, "root x stable on collapse")
        XCTAssertEqual(before.y, after.y, accuracy: 0.5, "root y stable on collapse")

        v.toggleCollapse(toCollapsed: false)
        XCTAssertNil(a.attribute(TopicAttribute.collapsed))
        after = rootCenter(v, root)
        XCTAssertEqual(before.x, after.x, accuracy: 0.5, "root x stable on expand")
        XCTAssertEqual(before.y, after.y, accuracy: 0.5, "root y stable on expand")
    }

    /// The real clamp test: inside a small scroll viewport, grow a left-side
    /// branch so much that the content would clip past the top-left edge. The
    /// canvas clamps the frames AND scrolls by the same delta, so the root must
    /// stay fixed *relative to the viewport* even though its absolute document
    /// frame shifts.
    func testLeftGrowthKeepsRootStableInViewport() {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let left = root.addChild(text: "Left"); left.setAttribute(TopicAttribute.leftSide, "true")
        left.addChild(text: "L1"); left.addChild(text: "L2")
        root.addChild(text: "Right").setAttribute(TopicAttribute.leftSide, "false")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        scroll.documentView = view
        view.display(map: map)

        func rootInViewport() -> CGPoint {
            let f = view.element(forTopic: root)!.frame
            let o = scroll.contentView.bounds.origin
            return CGPoint(x: f.midX - o.x, y: f.midY - o.y)
        }
        let before = rootInViewport()

        // Grow the left branch a lot — downward and leftward, forcing the clamp.
        for _ in 0..<12 { _ = left.addChild(text: "a fairly long extra child label") }
        view.rebuildElementsPublic()

        let after = rootInViewport()
        XCTAssertEqual(before.x, after.x, accuracy: 1.5,
                       "root holds its viewport x as the left branch grows past the edge")
        XCTAssertEqual(before.y, after.y, accuracy: 1.5,
                       "root holds its viewport y as the left branch grows past the edge")
    }
}
