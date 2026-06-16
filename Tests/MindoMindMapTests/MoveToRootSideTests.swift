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

    func testMoveRightOnRightChildDoesNotFlip() {
        // A right-side child pushed Right is "outward" — it must NOT flip to
        // left; it falls through to the normal indent/no-op path.
        let (view, _, a) = make()
        view.selectElement(view.element(forTopic: a))
        view.moveSelected(.right)
        XCTAssertEqual(a.attribute(TopicAttribute.leftSide), "false", "still on the right")
    }
}
