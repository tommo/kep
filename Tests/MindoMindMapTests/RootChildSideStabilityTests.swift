import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Guards the root-child left/right policy: new children of the root all go
/// to the RIGHT, the side is stamped explicitly at creation, and it never
/// gets recomputed from list position — so inserting or deleting a root
/// child can't swap the side of the others (the old index-parity instability).
@MainActor
final class RootChildSideStabilityTests: XCTestCase {

    private func makeView() -> (MindMapView, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        return (view, root)
    }

    /// Adding children straight to the root (select root → Tab, repeated)
    /// puts every one on the right, both as a stamped attribute and in the
    /// laid-out element.
    func testNewRootChildrenAllGoRight() {
        let (view, root) = makeView()
        for _ in 0..<5 {
            view.selectElement(view.element(forTopic: root))
            view.addChild()
        }
        XCTAssertEqual(root.children.count, 5)
        for child in root.children {
            XCTAssertEqual(child.attribute(TopicAttribute.leftSide), "false",
                           "new root child should be stamped right at creation")
            XCTAssertEqual(view.element(forTopic: child)?.isLeftSide, false,
                           "and laid out on the right side")
        }
    }

    /// The core stability fix: with the sides stamped, deleting a root child
    /// leaves every other child on the side it was already on. Under the old
    /// index-parity fallback, removing a child shifted later indices and
    /// flipped their sides across the root.
    func testDeletingRootChildDoesNotFlipOthers() {
        let (view, root) = makeView()
        for _ in 0..<6 {
            view.selectElement(view.element(forTopic: root))
            view.addChild()
        }
        // Drag two of them to the left so the map is genuinely two-sided.
        root.children[1].setAttribute(TopicAttribute.leftSide, "true")
        root.children[4].setAttribute(TopicAttribute.leftSide, "true")
        view.display(map: view.mindMap!)

        // Snapshot each surviving child's side keyed by identity.
        let survivors = [root.children[0], root.children[2], root.children[3], root.children[5]]
        let before = survivors.map { view.element(forTopic: $0)!.isLeftSide }

        // Delete child[1] (a left one) — indices of everything after it shift.
        view.undoableRemove(root.children[1])

        let after = survivors.map { view.element(forTopic: $0)!.isLeftSide }
        XCTAssertEqual(before, after, "no surviving root child should change sides when a sibling is deleted")
        // And the explicitly-left one is still on the left.
        XCTAssertEqual(view.element(forTopic: root.children[3])!.isLeftSide,
                       root.children[3].attribute(TopicAttribute.leftSide) == "true")
    }

    /// Legacy / imported root children with no `leftSide` attribute default
    /// to the right rather than alternating by position.
    func testUnattributedLegacyChildrenDefaultRight() {
        let (view, root) = makeView()
        // Build directly on the model (no stamp), as an old file would load.
        let a = root.addChild(text: "A")
        let b = root.addChild(text: "B")
        let c = root.addChild(text: "C")
        view.display(map: view.mindMap!)
        for t in [a, b, c] {
            XCTAssertEqual(view.element(forTopic: t)?.isLeftSide, false,
                           "\(t.text) without a leftSide attribute should default right, not alternate")
        }
    }
}
