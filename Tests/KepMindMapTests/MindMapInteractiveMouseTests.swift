import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// Real-mouse interaction tests: left-click select, double-click to edit,
/// Cmd-click multi-select, empty-canvas click to deselect — all posted as
/// genuine NSEvents through the window so hit-testing and mouseDown/mouseUp
/// run for real.
@MainActor
final class MindMapInteractiveMouseTests: XCTestCase {

    private func make() throws -> (WindowedMindMap, Topic, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let a = root.addChild(text: "A")
        let b = root.addChild(text: "B")
        let h = WindowedMindMap(map: map)
        // field-editor availability probe (double-click test needs it)
        h.view.selectElement(h.view.element(forTopic: root))
        h.view.beginInlineEdit(on: h.view.element(forTopic: root)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        try XCTSkipIf(!ok, "headless host can't provide a field editor")
        return (h, root, a, b)
    }

    func testSingleClickSelectsTopic() throws {
        let (h, _, a, _) = try make()
        h.view.selectElement(nil)
        h.click(topic: a)
        XCTAssertTrue(h.view.selectedElement?.topic === a, "click selects the topic under the cursor")
    }

    func testClickingDifferentTopicMovesSelection() throws {
        let (h, _, a, b) = try make()
        h.click(topic: a)
        XCTAssertTrue(h.view.selectedElement?.topic === a)
        h.click(topic: b)
        XCTAssertTrue(h.view.selectedElement?.topic === b)
        XCTAssertEqual(h.view.selectedTopics.count, 1, "plain click replaces, doesn't accumulate")
    }

    func testDoubleClickEntersEditMode() throws {
        let (h, _, a, _) = try make()
        h.click(topic: a, clickCount: 2)
        XCTAssertNotNil(h.view.inlineEditor, "double-click opens the editor")
        XCTAssertTrue(h.view.inlineEditTarget === a)
        XCTAssertEqual(h.editorText, "A")
    }

    func testCmdClickAddsToSelection() throws {
        let (h, _, a, b) = try make()
        h.click(topic: a)
        h.click(topic: b, mods: [.command])
        XCTAssertEqual(h.view.selectedTopics.count, 2, "Cmd-click extends the selection")
        XCTAssertTrue(h.view.selectedTopics.contains(ObjectIdentifier(a.self)))
        XCTAssertTrue(h.view.selectedTopics.contains(ObjectIdentifier(b.self)))
    }

    func testClickEmptyCanvasClearsSelection() throws {
        let (h, _, a, _) = try make()
        h.click(topic: a)
        XCTAssertNotNil(h.view.selectedElement)
        // A corner far from any topic.
        h.click(viewPoint: CGPoint(x: h.view.bounds.maxX - 4, y: h.view.bounds.maxY - 4))
        XCTAssertNil(h.view.selectedElement, "clicking empty space deselects")
    }

    func testDoubleClickThenTypeReplacesText() throws {
        let (h, _, a, _) = try make()
        h.click(topic: a, clickCount: 2)
        h.sendKey("N"); h.sendKey("o")        // replaces "A" via the live field editor
        XCTAssertEqual(h.editorText, "No")
    }
}
