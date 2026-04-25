import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

@MainActor
final class InsertSiblingTests: XCTestCase {

    /// Build Root → [A, B, C] (B selected) so we can verify where new
    /// siblings land. Bug #40: addNextSibling used to append to the end
    /// instead of inserting right after the current selection.
    private func makeFixture() -> (MindMapView, root: Topic, a: Topic, b: Topic, c: Topic) {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        let b = root.addChild(text: "B")
        let c = root.addChild(text: "C")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.selectElement(view.element(forTopic: b))
        return (view, root, a, b, c)
    }

    func testAddNextSiblingInsertsRightAfterSelection() {
        let (view, root, a, b, c) = makeFixture()
        view.addNextSibling()
        // Expect [A, B, NEW, C] — not [A, B, C, NEW].
        XCTAssertEqual(root.children.count, 4)
        XCTAssertTrue(root.children[0] === a)
        XCTAssertTrue(root.children[1] === b)
        XCTAssertTrue(root.children[3] === c)
        XCTAssertFalse(root.children[2] === a || root.children[2] === b || root.children[2] === c,
                       "child[2] should be the freshly inserted sibling")
    }

    func testAddPreviousSiblingInsertsRightBeforeSelection() {
        let (view, root, a, b, c) = makeFixture()
        view.addPreviousSibling()
        // Expect [A, NEW, B, C].
        XCTAssertEqual(root.children.count, 4)
        XCTAssertTrue(root.children[0] === a)
        XCTAssertTrue(root.children[2] === b)
        XCTAssertTrue(root.children[3] === c)
    }

    func testAddSiblingAtRootStampsLeftSideAttribute() {
        let (view, root, _, b, _) = makeFixture()
        // Force B onto the left side via the same attribute the renderer reads.
        b.setAttribute(TopicAttribute.leftSide, "true")
        view.display(map: view.mindMap!)
        view.selectElement(view.element(forTopic: b))

        view.addNextSibling()
        let new = root.children[2]
        // Bug #39: the new sibling at idx+1 would otherwise alternate to
        // the right side; the editor should stamp leftSide=true so it
        // stays on the left next to its source sibling.
        XCTAssertEqual(new.attribute(TopicAttribute.leftSide), "true")
    }
}
