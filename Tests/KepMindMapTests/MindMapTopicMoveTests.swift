import XCTest
import KepModel
@testable import KepMindMap

final class MindMapTopicMoveTests: XCTestCase {

    // root
    //  ├─ a
    //  │   ├─ a1
    //  │   └─ a2
    //  ├─ b
    //  └─ c
    private func tree() -> (root: Topic, a: Topic, a1: Topic, a2: Topic, b: Topic, c: Topic) {
        let root = Topic(text: "root")
        let a = root.addChild(text: "a")
        let a1 = a.addChild(text: "a1")
        let a2 = a.addChild(text: "a2")
        let b = root.addChild(text: "b")
        let c = root.addChild(text: "c")
        return (root, a, a1, a2, b, c)
    }

    func testRootCannotMove() {
        let t = tree()
        for dir in [MindMapView.Direction.up, .down, .left, .right] {
            XCTAssertNil(MindMapTopicMove.plan(for: t.root, direction: dir))
        }
    }

    func testUpReordersAmongSiblings() {
        let t = tree()
        // b is at index 1 of root; up -> index 0.
        let plan = MindMapTopicMove.plan(for: t.b, direction: .up)
        XCTAssertTrue(plan?.parent === t.root)
        XCTAssertEqual(plan?.index, 0)
    }

    func testUpAtFirstSiblingIsNil() {
        let t = tree()
        XCTAssertNil(MindMapTopicMove.plan(for: t.a, direction: .up))   // a is index 0
    }

    func testDownReordersAmongSiblings() {
        let t = tree()
        // a at index 0; down -> index 1.
        let plan = MindMapTopicMove.plan(for: t.a, direction: .down)
        XCTAssertTrue(plan?.parent === t.root)
        XCTAssertEqual(plan?.index, 1)
    }

    func testDownAtLastSiblingIsNil() {
        let t = tree()
        XCTAssertNil(MindMapTopicMove.plan(for: t.c, direction: .down))  // c is last
    }

    func testRightIndentsUnderPrecedingSibling() {
        let t = tree()
        // b (index 1 of root) indents under a (its preceding sibling). a has
        // 2 children, so b lands at index 2 (appended).
        let plan = MindMapTopicMove.plan(for: t.b, direction: .right)
        XCTAssertTrue(plan?.parent === t.a)
        XCTAssertEqual(plan?.index, 2)
    }

    func testRightWithNoPrecedingSiblingIsNil() {
        let t = tree()
        XCTAssertNil(MindMapTopicMove.plan(for: t.a, direction: .right))  // a has no prev sibling
    }

    func testLeftOutdentsAfterParentInGrandparent() {
        let t = tree()
        // a1 is a child of a (a is index 0 in root). Outdent -> grandparent
        // root, just after a -> index 1.
        let plan = MindMapTopicMove.plan(for: t.a1, direction: .left)
        XCTAssertTrue(plan?.parent === t.root)
        XCTAssertEqual(plan?.index, 1)
    }

    func testLeftWhenParentIsRootIsNil() {
        let t = tree()
        XCTAssertNil(MindMapTopicMove.plan(for: t.b, direction: .left))  // b's parent is root
    }

    /// End-to-end on the model: applying the .right plan via the same
    /// append+move steps `undoableReparent` uses lands b last under a.
    func testApplyingRightPlanMovesTopic() {
        let t = tree()
        let plan = MindMapTopicMove.plan(for: t.b, direction: .right)!
        t.root.removeChild(t.b)
        plan.parent.append(t.b)
        plan.parent.move(child: t.b, to: plan.index)
        XCTAssertTrue(t.b.parent === t.a)
        XCTAssertEqual(t.a.children.map { $0.text }, ["a1", "a2", "b"])
        XCTAssertEqual(t.root.children.map { $0.text }, ["a", "c"])
    }
}
