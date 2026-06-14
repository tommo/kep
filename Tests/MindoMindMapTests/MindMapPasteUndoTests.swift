import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

@MainActor
final class MindMapPasteUndoTests: XCTestCase {

    /// Bug (found by the adversarial bug-hunt): pasting topics appended them
    /// then called undoableReparent, making oldParent == newParent, so undo
    /// merely repositioned the pasted node instead of removing it — paste was
    /// un-undoable. undoableInsert fixes the undo semantics.
    func testUndoRemovesASinglePastedTopic() {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let target = root.addChild(text: "target")
        let (view, undo) = makeHeadlessMindMapWithUndo(map: map)

        // Put one topic on the pasteboard, select target, paste.
        let copied = Topic(text: "copied")
        let data = try! TopicSubtreeCodec.encode(copied)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: NSPasteboard.PasteboardType(TopicSubtreeCodec.pasteboardType))
        view.selectElement(view.element(forTopic: target))

        view.paste(nil)
        XCTAssertEqual(target.children.map(\.text), ["copied"], "paste grafts the topic")

        undo.undo()
        XCTAssertTrue(target.children.isEmpty, "undo must REMOVE the pasted topic")
    }

    func testUndoRemovesAllToppicsFromForestPaste() {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let target = root.addChild(text: "target")
        let (view, undo) = makeHeadlessMindMapWithUndo(map: map)

        let a = Topic(text: "A"); let b = Topic(text: "B")
        let data = try! TopicSubtreeCodec.encodeForest([a, b])
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: NSPasteboard.PasteboardType(TopicSubtreeCodec.pasteboardType))
        view.selectElement(view.element(forTopic: target))

        view.paste(nil)
        XCTAssertEqual(target.children.map(\.text), ["A", "B"])

        undo.undo()   // one grouped undo removes both
        XCTAssertTrue(target.children.isEmpty, "a single undo removes the whole pasted forest")
    }

    func testRedoReinsertsPastedTopics() {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let target = root.addChild(text: "target")
        let (view, undo) = makeHeadlessMindMapWithUndo(map: map)

        let data = try! TopicSubtreeCodec.encode(Topic(text: "X"))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: NSPasteboard.PasteboardType(TopicSubtreeCodec.pasteboardType))
        view.selectElement(view.element(forTopic: target))
        view.paste(nil)
        undo.undo()
        XCTAssertTrue(target.children.isEmpty)
        undo.redo()
        XCTAssertEqual(target.children.map(\.text), ["X"], "redo re-inserts")
    }
}
