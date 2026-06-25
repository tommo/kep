import XCTest
@testable import KepModel

final class TopicMoveTests: XCTestCase {

    /// Build  Root[ A[A1,A2], B, C ]  and return (root, lookup-by-text).
    private func tree() -> Topic {
        let root = Topic(text: "Root")
        let a = root.addChild(text: "A")
        _ = a.addChild(text: "A1")
        _ = a.addChild(text: "A2")
        _ = root.addChild(text: "B")
        _ = root.addChild(text: "C")
        return root
    }

    private func child(_ t: Topic, _ text: String) -> Topic {
        t.children.first { $0.text == text } ?? t.children.flatMap { [$0] + $0.children }.first { $0.text == text }!
    }

    /// Apply a move exactly as MindMapView.undoableReparent does
    /// (remove → append → move), using the pure plan.
    private func apply(_ topic: Topic, _ move: TopicMove) -> Bool {
        guard let plan = topic.movePlan(move), let old = topic.parent else { return false }
        old.removeChild(topic)
        plan.newParent.append(topic)
        plan.newParent.move(child: topic, to: plan.index)
        return true
    }

    func testMoveDownSwapsWithNextSibling() {
        let root = tree()
        XCTAssertTrue(apply(child(root, "B"), .down))
        XCTAssertEqual(root.children.map(\.text), ["A", "C", "B"])
    }

    func testMoveUpSwapsWithPreviousSibling() {
        let root = tree()
        XCTAssertTrue(apply(child(root, "C"), .up))
        XCTAssertEqual(root.children.map(\.text), ["A", "C", "B"])
    }

    func testMoveDownAtEndIsRejected() {
        let root = tree()
        XCTAssertFalse(apply(child(root, "C"), .down))   // already last
        XCTAssertEqual(root.children.map(\.text), ["A", "B", "C"])
    }

    func testMoveUpAtStartIsRejected() {
        let root = tree()
        XCTAssertFalse(apply(child(root, "A"), .up))
    }

    func testIndentBecomesLastChildOfPreviousSibling() {
        let root = tree()
        XCTAssertTrue(apply(child(root, "B"), .indent))  // B → under A
        XCTAssertEqual(root.children.map(\.text), ["A", "C"])
        XCTAssertEqual(child(root, "A").children.map(\.text), ["A1", "A2", "B"])
        XCTAssertTrue(child(root, "B").parent === child(root, "A"))
    }

    func testIndentFirstChildRejected() {
        let root = tree()
        XCTAssertFalse(apply(child(root, "A"), .indent)) // no previous sibling
    }

    func testOutdentBecomesParentsNextSibling() {
        let root = tree()
        let a1 = child(root, "A1")
        XCTAssertTrue(apply(a1, .outdent))               // A1 → between A and B
        XCTAssertEqual(root.children.map(\.text), ["A", "A1", "B", "C"])
        XCTAssertEqual(child(root, "A").children.map(\.text), ["A2"])
    }

    func testOutdentTopLevelRejected() {
        let root = tree()
        XCTAssertFalse(apply(child(root, "B"), .outdent)) // parent is root (no grandparent)
    }

    func testRootHasNoPlan() {
        XCTAssertNil(tree().movePlan(.up))
    }
}
