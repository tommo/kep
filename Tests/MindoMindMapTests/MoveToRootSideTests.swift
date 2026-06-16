import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// ⌘+arrow on a root child flips which side of the root it hangs off — the only
/// way to put nodes on the root's left side (a root child has no grandparent to
/// outdent into).
@MainActor
final class MoveToRootSideTests: XCTestCase {

    private func make() -> (MindMapView, root: Topic, a: Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A")
        a.setAttribute(TopicAttribute.leftSide, "false")   // start on the right
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        return (view, root, a)
    }

    func testMoveLeftPutsRootChildOnLeftSide() {
        let (view, _, a) = make()
        view.selectElement(view.element(forTopic: a))
        view.moveSelected(.left)
        XCTAssertEqual(a.attribute(TopicAttribute.leftSide), "true", "A moved to the left side")
        XCTAssertTrue(view.element(forTopic: a)?.isLeftSide ?? false, "layout reflects the left side")
    }

    func testMoveRightReturnsLeftChildToRight() {
        let (view, _, a) = make()
        a.setAttribute(TopicAttribute.leftSide, "true")    // now on the left
        view.rebuildElementsPublic()
        view.selectElement(view.element(forTopic: a))
        view.moveSelected(.right)
        XCTAssertEqual(a.attribute(TopicAttribute.leftSide), "false", "A moved back to the right side")
        XCTAssertFalse(view.element(forTopic: a)?.isLeftSide ?? true)
    }

    func testContextMenuMoveToSideFlips() {
        let (view, _, a) = make()
        view.selectElement(view.element(forTopic: a))
        let item = NSMenuItem()
        item.representedObject = view.element(forTopic: a)
        view.contextMoveToSide(item)
        XCTAssertEqual(a.attribute(TopicAttribute.leftSide), "true", "context action moved A to the left")
    }

    func testDragBesideRootDetectsLeftSide() {
        let (view, root, a) = make()
        let aEl = view.element(forTopic: a)!
        let rf = view.element(forTopic: root)!.frame
        // A point out to the LEFT of the root, level with it.
        let p = CGPoint(x: rf.minX - 40, y: rf.midY)
        let hit = view.rootSideInsertion(under: p, source: aEl)
        XCTAssertNotNil(hit, "cursor beside the root's left is a root-side drop zone")
        XCTAssertEqual(hit?.isLeft, true)
        XCTAssertTrue(hit?.target.parent.topic === root, "drops as a child of root")
    }

    func testCursorOverANodeIsNotASideDrop() {
        // Over an actual node, the node is the drop target — not a root-side
        // placement (regression: dragging onto a right child was hijacked).
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A"); a.setAttribute(TopicAttribute.leftSide, "false")
        let b = root.addChild(text: "B"); b.setAttribute(TopicAttribute.leftSide, "false")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let aEl = view.element(forTopic: a)!
        let bFrame = view.element(forTopic: b)!.frame
        let overB = CGPoint(x: bFrame.midX, y: bFrame.midY)
        XCTAssertNil(view.rootSideInsertion(under: overB, source: aEl),
                     "a node under the cursor wins over a root-side drop")
    }

    func testDragFarFromRootIsNotASideDrop() {
        let (view, root, a) = make()
        let aEl = view.element(forTopic: a)!
        let rf = view.element(forTopic: root)!.frame
        // Well below the root's vertical band → not a side drop.
        let p = CGPoint(x: rf.minX - 40, y: rf.maxY + 400)
        XCTAssertNil(view.rootSideInsertion(under: p, source: aEl))
    }

    func testMoveRightOnRightChildDoesNotFlip() {
        // A right-side child pushed Right is "outward" — it must NOT flip to
        // left; it falls through to the normal indent/no-op path.
        let (view, _, a) = make()
        view.selectElement(view.element(forTopic: a))
        view.moveSelected(.right)
        XCTAssertEqual(a.attribute(TopicAttribute.leftSide), "false", "still on the right")
    }
}
