import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Real-event coverage of two interaction areas that only misbehave through
/// the actual responder chain / mouse pipeline: committing an edit by
/// clicking away, and drag-to-reparent.
@MainActor
final class MindMapInteractiveDragEditTests: XCTestCase {

    private func make() throws -> (WindowedMindMap, Topic, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let a = root.addChild(text: "A")
        let b = root.addChild(text: "B")
        let h = WindowedMindMap(map: map)
        h.view.selectElement(h.view.element(forTopic: root))
        h.view.beginInlineEdit(on: h.view.element(forTopic: root)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        try XCTSkipIf(!ok, "headless host can't provide a field editor")
        return (h, root, a, b)
    }

    // MARK: - Click-away commits the edit

    func testClickingAnotherTopicCommitsTheEdit() throws {
        let (h, _, a, b) = try make()
        h.click(topic: a, clickCount: 2)        // edit A
        h.sendKey("Z")                          // "Z" replaces "A"
        XCTAssertEqual(h.editorText, "Z")
        h.click(topic: b)                       // click B → should commit A and select B
        XCTAssertEqual(a.text, "Z", "clicking away commits the edit")
        XCTAssertNil(h.view.inlineEditor, "editor closed")
        XCTAssertTrue(h.view.selectedElement?.topic === b, "and selects the clicked topic")
    }

    // MARK: - Drag to reparent

    func testDragTopicOntoAnotherReparentsIt() throws {
        let (h, _, a, b) = try make()
        XCTAssertTrue(a.parent === b.parent, "A and B start as siblings under root")
        h.drag(topic: a, onto: b)
        XCTAssertTrue(a.parent === b, "dragging A onto B makes A a child of B")
    }

    func testDragOntoSelfDoesNothing() throws {
        let (h, root, a, _) = try make()
        h.drag(topic: a, onto: a)
        XCTAssertTrue(a.parent === root, "dragging a topic onto itself leaves it put")
    }

    // MARK: - Marquee (rubber-band) selection via real drag

    func testMarqueeDragSelectsEnclosedTopics() throws {
        let (h, _, _, _) = try make()
        h.view.selectElement(nil)
        // Drag a rectangle spanning the whole canvas from an empty corner —
        // it must rubber-band-select multiple topics (root + A + B).
        h.drag(from: CGPoint(x: 2, y: 2),
               to: CGPoint(x: h.view.bounds.maxX - 2, y: h.view.bounds.maxY - 2))
        XCTAssertGreaterThanOrEqual(h.view.selectedTopics.count, 2,
                                    "marquee over the canvas selects multiple topics")
    }

    func testTinyClickDragOnEmptyDoesNotSelectEverything() throws {
        let (h, _, _, _) = try make()
        h.view.selectElement(nil)
        // A near-zero drag in an empty corner is effectively a click → clears.
        h.drag(from: CGPoint(x: 3, y: 3), to: CGPoint(x: 4, y: 4), steps: 1)
        XCTAssertTrue(h.view.selectedTopics.isEmpty, "a click in empty space selects nothing")
    }

    func testDragReparentIsUndoable() throws {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let a = root.addChild(text: "A")
        let b = root.addChild(text: "B")
        let (view, undo) = makeHeadlessMindMapWithUndo(map: map)
        // Use the headless view's drag via direct calls isn't possible; assert
        // the model-level reparent + undo instead (covered live by the windowed
        // drag test above for the gesture path).
        view.selectElement(view.element(forTopic: a))
        view.undoableReparent(a, to: b, at: b.children.count)
        XCTAssertTrue(a.parent === b)
        undo.undo()
        XCTAssertTrue(a.parent === root, "undo restores A under root")
    }
}
