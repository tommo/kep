import XCTest
import KepModel
@testable import KepMindMap

final class MindMapSelectionTests: XCTestCase {

    // root ─ a ─ a1
    //            a2
    //      ─ b
    private func tree() -> (root: Topic, a: Topic, a1: Topic, a2: Topic, b: Topic) {
        let root = Topic(text: "root")
        let a = root.addChild(text: "a")
        let a1 = a.addChild(text: "a1")
        let a2 = a.addChild(text: "a2")
        let b = root.addChild(text: "b")
        return (root, a, a1, a2, b)
    }

    func testDisjointTopicsAllSurvive() {
        let t = tree()
        let result = MindMapSelection.topLevel([t.a, t.b])
        XCTAssertEqual(result.map(\.text), ["a", "b"])
    }

    func testDescendantOfSelectedAncestorIsPruned() {
        let t = tree()
        // a and a1 selected → a1 is dropped (covered by a's subtree).
        let result = MindMapSelection.topLevel([t.a, t.a1])
        XCTAssertEqual(result.map(\.text), ["a"])
    }

    func testDeepDescendantPruned() {
        let root = Topic(text: "r")
        let x = root.addChild(text: "x")
        let y = x.addChild(text: "y")
        let z = y.addChild(text: "z")
        let result = MindMapSelection.topLevel([x, z])   // z is x's grandchild
        XCTAssertEqual(result.map(\.text), ["x"])
    }

    func testSiblingsBothSurvive() {
        let t = tree()
        let result = MindMapSelection.topLevel([t.a1, t.a2])   // siblings, neither nests the other
        XCTAssertEqual(result.map(\.text), ["a1", "a2"])
    }

    func testInputOrderPreserved() {
        let t = tree()
        let result = MindMapSelection.topLevel([t.b, t.a])
        XCTAssertEqual(result.map(\.text), ["b", "a"])
    }

    func testEmptyInput() {
        XCTAssertTrue(MindMapSelection.topLevel([]).isEmpty)
    }

    // MARK: - reparentable (multi-select drag)

    func testReparentableMovesDisjointTopicsUnderNewParent() {
        let t = tree()
        let result = MindMapSelection.reparentable([t.a1, t.a2], under: t.b)
        XCTAssertEqual(result.map(\.text), ["a1", "a2"])
    }

    func testReparentableDropsTopicAlreadyChildOfTarget() {
        let t = tree()
        // a1 is already a child of a → dropping it onto a is a no-op.
        let result = MindMapSelection.reparentable([t.a1, t.b], under: t.a)
        XCTAssertEqual(result.map(\.text), ["b"])
    }

    func testReparentableRejectsDroppingOntoOwnDescendant() {
        let t = tree()
        // Can't move a under a2 (a2 is inside a's subtree → cycle).
        let result = MindMapSelection.reparentable([t.a], under: t.a2)
        XCTAssertTrue(result.isEmpty)
    }

    func testReparentableRejectsDroppingOntoItself() {
        let t = tree()
        XCTAssertTrue(MindMapSelection.reparentable([t.a], under: t.a).isEmpty)
    }

    func testReparentablePrunesDescendantsThenValidates() {
        let t = tree()
        // a and a1 selected, dropping onto b: a1 pruned (under a), a moves.
        let result = MindMapSelection.reparentable([t.a, t.a1], under: t.b)
        XCTAssertEqual(result.map(\.text), ["a"])
    }

    // MARK: - Forest codec

    func testForestRoundTripMultipleTopics() throws {
        let a = Topic(text: "alpha"); a.addChild(text: "a-child")
        let b = Topic(text: "beta")
        let data = try TopicSubtreeCodec.encodeForest([a, b])
        let back = try TopicSubtreeCodec.decodeForest(data)
        XCTAssertEqual(back.map(\.text), ["alpha", "beta"])
        XCTAssertEqual(back[0].children.map(\.text), ["a-child"])
    }

    func testDecodeForestAcceptsLegacySingleTopic() throws {
        // Old single-topic payloads must still paste as a one-element forest.
        let single = try TopicSubtreeCodec.encode(Topic(text: "solo"))
        let forest = try TopicSubtreeCodec.decodeForest(single)
        XCTAssertEqual(forest.map(\.text), ["solo"])
    }

    func testEncodeForestSingleRoundTrips() throws {
        let data = try TopicSubtreeCodec.encodeForest([Topic(text: "one")])
        XCTAssertEqual(try TopicSubtreeCodec.decodeForest(data).map(\.text), ["one"])
    }
}
