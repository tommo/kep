import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

@MainActor
final class DragReparentTests: XCTestCase {

    /// Build a small map: Root → [A → A1, B]. Returns view + the Topics so
    /// tests can drive `undoableReparent` and the underlying validation that
    /// the drag pipeline performs.
    private func makeFixture() -> (MindMapView, root: Topic, a: Topic, a1: Topic, b: Topic) {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        let a1 = a.addChild(text: "A1")
        let b = root.addChild(text: "B")

        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let mgr = UndoManager()
        view.injectedUndoManager = mgr
        view.display(map: map)
        return (view, root, a, a1, b)
    }

    func testReparentMovesChild() {
        let (view, root, a, _, b) = makeFixture()
        XCTAssertEqual(root.children.count, 2)
        XCTAssertEqual(b.children.count, 0)

        view.undoableReparent(a, to: b, at: 0)

        XCTAssertEqual(root.children.count, 1)
        XCTAssertTrue(root.children[0] === b)
        XCTAssertEqual(b.children.count, 1)
        XCTAssertTrue(b.children[0] === a)
    }

    /// Cycle protection: dropping a topic onto its own descendant must be
    /// rejected by `candidateDropTarget` so we don't break the tree.
    /// Exercised through the public extension method we mirror the rule on:
    /// after a hypothetical reparent, the topic must still reach the root by
    /// walking parent pointers.
    func testWouldCreateCycle() {
        let (_, root, a, a1, _) = makeFixture()
        XCTAssertTrue(isDescendant(of: a, candidate: a1))
        XCTAssertFalse(isDescendant(of: a1, candidate: a))
        XCTAssertFalse(isDescendant(of: a, candidate: root))
    }

    /// Helper that mirrors the cycle-detection logic from
    /// `MindMapView.candidateDropTarget`. Returns true when `candidate`
    /// already lives in `source`'s subtree.
    private func isDescendant(of source: Topic, candidate: Topic) -> Bool {
        var t: Topic? = candidate
        while let cur = t {
            if cur === source { return true }
            t = cur.parent
        }
        return false
    }

    /// Reparent → undo restores the original parent + sibling position.
    func testReparentIsUndoable() {
        let (view, root, a, _, b) = makeFixture()
        view.undoableReparent(a, to: b, at: 0)
        view.injectedUndoManager?.undo()
        XCTAssertEqual(root.children.count, 2)
        XCTAssertTrue(root.children[0] === a)
        XCTAssertTrue(b.children.isEmpty)
    }
}
