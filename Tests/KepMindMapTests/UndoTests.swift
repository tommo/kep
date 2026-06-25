import XCTest
import AppKit
import KepModel
@testable import KepMindMap

@MainActor
final class MindMapUndoTests: XCTestCase {

    private func makeView() -> (MindMapView, UndoManager) {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        _ = root.addChild(text: "Original")
        return makeHeadlessMindMapWithUndo(map: map)
    }

    func testAddChildIsUndoable() {
        let (view, mgr) = makeView()
        let root = view.mindMap!.root!
        XCTAssertEqual(root.children.count, 1)
        _ = view.undoableAddChild(to: root, text: "New child")
        XCTAssertEqual(root.children.count, 2)

        XCTAssertTrue(mgr.canUndo)
        mgr.undo()
        XCTAssertEqual(root.children.count, 1)

        XCTAssertTrue(mgr.canRedo)
        mgr.redo()
        XCTAssertEqual(root.children.count, 2)
    }

    func testSetTextIsUndoable() {
        let (view, mgr) = makeView()
        let leaf = view.mindMap!.root!.children[0]
        view.undoableSetText(leaf, to: "Renamed")
        XCTAssertEqual(leaf.text, "Renamed")
        mgr.undo()
        XCTAssertEqual(leaf.text, "Original")
        mgr.redo()
        XCTAssertEqual(leaf.text, "Renamed")
    }

    func testRemoveIsUndoable() {
        let (view, mgr) = makeView()
        let root = view.mindMap!.root!
        let leaf = root.children[0]
        view.undoableRemove(leaf)
        XCTAssertTrue(root.children.isEmpty)
        mgr.undo()
        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(root.children[0].text, "Original")
    }

    func testCollapseAttributeIsUndoable() {
        let (view, mgr) = makeView()
        let leaf = view.mindMap!.root!.children[0]
        view.undoableSetAttribute(leaf, key: TopicAttribute.collapsed, value: "true")
        XCTAssertEqual(leaf.attribute(TopicAttribute.collapsed), "true")
        mgr.undo()
        XCTAssertNil(leaf.attribute(TopicAttribute.collapsed))
        mgr.redo()
        XCTAssertEqual(leaf.attribute(TopicAttribute.collapsed), "true")
    }

    func testReparentIsUndoable() {
        let (view, mgr) = makeView()
        let root = view.mindMap!.root!
        _ = root.addChild(text: "A")
        let target = root.children.last!  // 'A'
        let toMove = root.children[0]     // 'Original'

        view.undoableReparent(toMove, to: target, at: 0)
        XCTAssertEqual(target.children.count, 1)
        XCTAssertEqual(root.children.count, 1)
        XCTAssertEqual(target.children[0].text, "Original")

        mgr.undo()
        XCTAssertEqual(root.children.count, 2)
        XCTAssertTrue(target.children.isEmpty)
    }
}
