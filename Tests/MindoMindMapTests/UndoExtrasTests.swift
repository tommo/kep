import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

@MainActor
final class UndoExtrasTests: XCTestCase {

    private func makeView() -> (MindMapView, Topic, UndoManager) {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let (view, mgr) = makeHeadlessMindMapWithUndo(map: map)
        return (view, root, mgr)
    }

    func testSetExtraIsUndoable() {
        let (view, topic, mgr) = makeView()
        XCTAssertNil(topic.extra(.note))
        view.undoableSetExtra(topic, .note, value: ExtraNote(text: "Hello"))
        XCTAssertEqual((topic.extra(.note) as? ExtraNote)?.text, "Hello")
        mgr.undo()
        XCTAssertNil(topic.extra(.note))
        mgr.redo()
        XCTAssertEqual((topic.extra(.note) as? ExtraNote)?.text, "Hello")
    }

    func testReplaceExtraIsUndoable() {
        let (view, topic, mgr) = makeView()
        view.undoableSetExtra(topic, .link, value: ExtraLink(uri: "https://a"))
        view.undoableSetExtra(topic, .link, value: ExtraLink(uri: "https://b"))
        XCTAssertEqual((topic.extra(.link) as? ExtraLink)?.uri, "https://b")
        mgr.undo()
        XCTAssertEqual((topic.extra(.link) as? ExtraLink)?.uri, "https://a")
        mgr.undo()
        XCTAssertNil(topic.extra(.link))
    }

    func testRemoveExtraIsUndoable() {
        let (view, topic, mgr) = makeView()
        view.undoableSetExtra(topic, .file, value: ExtraFile(uri: "/tmp/x"))
        view.undoableSetExtra(topic, .file, value: nil)
        XCTAssertNil(topic.extra(.file))
        mgr.undo()
        XCTAssertEqual((topic.extra(.file) as? ExtraFile)?.uri, "/tmp/x")
    }

    // MARK: - Bulk fold-all / unfold-all

    func testFoldAllCollapsesEveryParentInOneUndoStep() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        _ = a.addChild(text: "A1")
        let b = root.addChild(text: "B")
        _ = b.addChild(text: "B1")
        let leaf = root.addChild(text: "Leaf")
        let (view, mgr) = makeHeadlessMindMapWithUndo(map: map)

        view.setAllCollapsed(true)
        XCTAssertEqual(root.attribute(TopicAttribute.collapsed), "true")
        XCTAssertEqual(a.attribute(TopicAttribute.collapsed), "true")
        XCTAssertEqual(b.attribute(TopicAttribute.collapsed), "true")
        // Leaf has no children — must not gain a collapsed flag.
        XCTAssertNil(leaf.attribute(TopicAttribute.collapsed))

        // Single undo step rolls back every flip at once.
        mgr.undo()
        XCTAssertNil(root.attribute(TopicAttribute.collapsed))
        XCTAssertNil(a.attribute(TopicAttribute.collapsed))
        XCTAssertNil(b.attribute(TopicAttribute.collapsed))
    }

    func testUnfoldAllRestoresPriorFoldStateOnUndo() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        _ = a.addChild(text: "A1")
        a.setAttribute(TopicAttribute.collapsed, "true")
        let (view, mgr) = makeHeadlessMindMapWithUndo(map: map)

        view.setAllCollapsed(false)
        XCTAssertNil(a.attribute(TopicAttribute.collapsed))
        mgr.undo()
        XCTAssertEqual(a.attribute(TopicAttribute.collapsed), "true")
    }

    func testFoldAllIsNoOpWhenAlreadyFullyFolded() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        _ = a.addChild(text: "A1")
        let (view, mgr) = makeHeadlessMindMapWithUndo(map: map)
        view.setAllCollapsed(true)
        let firstUndoCount = mgr.canUndo
        XCTAssertTrue(firstUndoCount)
        // Calling again should not register another undo step.
        view.setAllCollapsed(true)
        mgr.undo()  // Reverses the *first* call.
        XCTAssertFalse(mgr.canUndo, "second call must not stack a redundant undo entry")
    }
}
