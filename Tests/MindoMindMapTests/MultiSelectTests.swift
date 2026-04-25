import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

@MainActor
final class MultiSelectTests: XCTestCase {

    private func makeView() -> (MindMapView, root: Topic, a: Topic, b: Topic, c: Topic, a1: Topic) {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        let b = root.addChild(text: "B")
        let c = root.addChild(text: "C")
        let a1 = a.addChild(text: "A1")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        return (view, root, a, b, c, a1)
    }

    func testToggleSelectionAddsAndRemoves() {
        let (view, _, a, b, _, _) = makeView()
        // Start with A primary.
        view.selectElement(view.element(forTopic: a))
        XCTAssertEqual(view.selectedTopics.count, 1)

        // Cmd-click B → both selected, B becomes primary.
        view.toggleSelection(view.element(forTopic: b))
        XCTAssertEqual(view.selectedTopics.count, 2)
        XCTAssertTrue(view.selectedElement?.topic === b)

        // Cmd-click B again → removed.
        view.toggleSelection(view.element(forTopic: b))
        XCTAssertEqual(view.selectedTopics.count, 1)
    }

    func testExtendSelectionDownAddsSibling() {
        // With 3 root children, layout balances them: A right, B left, C right.
        // A's same-side siblings are therefore [A, C], so .down from A picks C.
        let (view, _, a, _, c, _) = makeView()
        view.selectElement(view.element(forTopic: a))
        view.extendSelection(.down)
        XCTAssertTrue(view.selectedTopics.contains(ObjectIdentifier(a)))
        XCTAssertTrue(view.selectedTopics.contains(ObjectIdentifier(c)))
        XCTAssertTrue(view.selectedElement?.topic === c)
    }

    func testDeleteSelectionRemovesAllAndCollapsesToParent() {
        let (view, root, a, b, c, _) = makeView()
        view.selectElement(view.element(forTopic: a))
        view.toggleSelection(view.element(forTopic: c))
        XCTAssertEqual(view.selectedTopics.count, 2)
        // Synthesize a Delete keypress by calling the same internal entry
        // that keyDown does — `deleteSelection()` is private, so go via
        // the public route the responder uses.
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}",
            isARepeat: false, keyCode: 0x33
        )!
        view.keyDown(with: event)

        XCTAssertEqual(root.children.count, 1, "B should be the only survivor")
        XCTAssertTrue(root.children[0] === b)
    }

    func testDeletePrunesDescendantsAlreadyAccountedFor() {
        let (view, root, a, _, _, a1) = makeView()
        // Select both A and its child A1 — A's removal already covers A1.
        view.selectElement(view.element(forTopic: a))
        view.toggleSelection(view.element(forTopic: a1))
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}",
            isARepeat: false, keyCode: 0x33
        )!
        view.keyDown(with: event)
        // A is gone; B and C survive.
        XCTAssertEqual(root.children.count, 2)
        XCTAssertFalse(root.children.contains(where: { $0 === a }))
    }
}
