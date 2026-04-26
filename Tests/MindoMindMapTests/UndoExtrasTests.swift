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

    // MARK: - Clone topic

    func testCloneTopicInsertsAsNextSiblingAndIsUndoable() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        let b = root.addChild(text: "B")
        let (view, mgr) = makeHeadlessMindMapWithUndo(map: map)

        let clone = view.undoableCloneTopic(a, deep: false)
        XCTAssertNotNil(clone)
        // Order: A, clone, B.
        XCTAssertEqual(root.children.count, 3)
        XCTAssertTrue(root.children[0] === a)
        XCTAssertTrue(root.children[1] === clone)
        XCTAssertTrue(root.children[2] === b)

        mgr.undo()
        XCTAssertEqual(root.children.count, 2)
        XCTAssertTrue(root.children[0] === a)
        XCTAssertTrue(root.children[1] === b)
    }

    func testDeepCloneCarriesSubtree() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        _ = a.addChild(text: "A1")
        let (view, _) = makeHeadlessMindMapWithUndo(map: map)

        let clone = view.undoableCloneTopic(a, deep: true)
        XCTAssertEqual(clone?.children.count, 1)
        XCTAssertEqual(clone?.children.first?.text, "A1")
    }

    // MARK: - Convert multiline → subtree

    func testConvertMultilineSplitsLinesIntoChildren() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let t = root.addChild(text: "alpha\nbeta\ngamma")
        let (view, _) = makeHeadlessMindMapWithUndo(map: map)

        view.undoableConvertMultilineToChildren(t)
        XCTAssertEqual(t.text, "alpha")
        XCTAssertEqual(t.children.count, 2)
        XCTAssertEqual(t.children[0].text, "beta")
        XCTAssertEqual(t.children[1].text, "gamma")
    }

    func testConvertMultilineUndoRestoresOriginalText() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let t = root.addChild(text: "alpha\nbeta")
        let (view, mgr) = makeHeadlessMindMapWithUndo(map: map)

        view.undoableConvertMultilineToChildren(t)
        mgr.undo()
        XCTAssertEqual(t.text, "alpha\nbeta")
        XCTAssertTrue(t.children.isEmpty)
    }

    func testConvertSingleLineIsNoOp() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let t = root.addChild(text: "just one")
        let (view, mgr) = makeHeadlessMindMapWithUndo(map: map)

        view.undoableConvertMultilineToChildren(t)
        XCTAssertEqual(t.text, "just one")
        XCTAssertTrue(t.children.isEmpty)
        XCTAssertFalse(mgr.canUndo, "no-op must not register an undo entry")
    }

    func testConvertPreservesExistingChildren() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let t = root.addChild(text: "header\nfirst\nsecond")
        let pre = t.addChild(text: "pre-existing")
        let (view, _) = makeHeadlessMindMapWithUndo(map: map)

        view.undoableConvertMultilineToChildren(t)
        XCTAssertEqual(t.children.count, 3)
        XCTAssertTrue(t.children[0] === pre, "existing children stay first")
        XCTAssertEqual(t.children[1].text, "first")
        XCTAssertEqual(t.children[2].text, "second")
    }

    func testCloneRootIsNoOp() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let (view, _) = makeHeadlessMindMapWithUndo(map: map)
        XCTAssertNil(view.undoableCloneTopic(root, deep: false))
    }

    func testFoldSubtreeOnlyAffectsTheNamedBranch() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        _ = a.addChild(text: "A1")
        let b = root.addChild(text: "B")
        _ = b.addChild(text: "B1")
        let (view, mgr) = makeHeadlessMindMapWithUndo(map: map)

        view.undoableSetSubtreeCollapsed(rootedAt: a, collapsed: true)
        XCTAssertEqual(a.attribute(TopicAttribute.collapsed), "true")
        // Sibling branch B and root must be untouched.
        XCTAssertNil(b.attribute(TopicAttribute.collapsed))
        XCTAssertNil(root.attribute(TopicAttribute.collapsed))

        mgr.undo()
        XCTAssertNil(a.attribute(TopicAttribute.collapsed))
    }

    func testUnfoldSubtreeRecursesIntoNestedFolds() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        let a1 = a.addChild(text: "A1")
        _ = a1.addChild(text: "A1a")
        a.setAttribute(TopicAttribute.collapsed, "true")
        a1.setAttribute(TopicAttribute.collapsed, "true")
        let (view, _) = makeHeadlessMindMapWithUndo(map: map)

        view.undoableSetSubtreeCollapsed(rootedAt: a, collapsed: false)
        XCTAssertNil(a.attribute(TopicAttribute.collapsed))
        XCTAssertNil(a1.attribute(TopicAttribute.collapsed))
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
