import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// The editing-finish + creation model (XMind-aligned, per user correction):
/// while EDITING, Return/Tab/⇧Tab just COMMIT and keep the same topic
/// selected — never create, never warp. Node creation is a SELECTED-mode
/// action (Return = sibling, Tab = child). Driven through the real
/// NSTextFieldDelegate command path.
@MainActor
final class MindMapEditCreateFlowTests: XCTestCase {

    private func makeView() -> (MindMapView, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let a = root.addChild(text: "A")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        return (view, root, a)
    }

    @discardableResult
    private func command(_ view: MindMapView, _ selector: Selector) -> Bool {
        guard let field = view.inlineEditor else { return false }
        return view.control(field, textView: NSTextView(), doCommandBy: selector)
    }

    private func startEditing(_ view: MindMapView, _ topic: Topic) {
        view.selectElement(view.element(forTopic: topic))
        view.beginInlineEdit(on: view.element(forTopic: topic)!)
    }

    // MARK: - While editing: finishing keys COMMIT and STAY (no create, no warp)

    func testReturnWhileEditingCommitsAndStays() {
        let (view, root, a) = makeView()
        startEditing(view, a)
        view.inlineEditor?.stringValue = "Apple"
        XCTAssertTrue(command(view, #selector(NSResponder.insertNewline(_:))))
        XCTAssertEqual(a.text, "Apple", "committed")
        XCTAssertEqual(root.children.count, 1, "Return while editing must NOT create a sibling")
        XCTAssertNil(view.inlineEditor, "edit finished")
        XCTAssertTrue(view.selectedElement?.topic === a, "selection stays on the edited topic — no warp")
    }

    func testTabWhileEditingCommitsAndStays() {
        let (view, _, a) = makeView()
        startEditing(view, a)
        view.inlineEditor?.stringValue = "Parent"
        XCTAssertTrue(command(view, #selector(NSResponder.insertTab(_:))))
        XCTAssertEqual(a.text, "Parent")
        XCTAssertEqual(a.children.count, 0, "Tab while editing must NOT create a child")
        XCTAssertNil(view.inlineEditor)
        XCTAssertTrue(view.selectedElement?.topic === a, "no warp")
    }

    func testEscCancelsAndKeepsOriginalText() {
        let (view, root, a) = makeView()
        startEditing(view, a)
        view.inlineEditor?.stringValue = "throwaway"
        XCTAssertTrue(command(view, #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(a.text, "A", "Esc discards the edit")
        XCTAssertEqual(root.children.count, 1)
        XCTAssertNil(view.inlineEditor)
    }

    // MARK: - Selected-mode creation (keyDown, not editing)

    func testReturnOnSelectedTopicCreatesSiblingAndEdits() {
        let (view, root, a) = makeView()
        view.selectElement(view.element(forTopic: a))
        view.keyDown(with: key("\r"))
        XCTAssertEqual(root.children.count, 2, "Return on a selected topic creates a sibling")
        XCTAssertTrue(view.inlineEditTarget?.parent === root)
        XCTAssertNotNil(view.inlineEditor, "the new sibling is ready to type")
    }

    func testTabOnSelectedTopicCreatesChildAndEdits() {
        let (view, _, a) = makeView()
        view.selectElement(view.element(forTopic: a))
        view.keyDown(with: key("\t"))
        XCTAssertEqual(a.children.count, 1, "Tab on a selected topic creates a child")
        XCTAssertTrue(view.inlineEditTarget?.parent === a)
        XCTAssertNotNil(view.inlineEditor)
    }

    // MARK: - The realistic loop: type, finish, make next sibling

    func testTypeFinishThenMakeSiblingLoop() {
        let (view, root, a) = makeView()
        // edit A
        view.selectElement(view.element(forTopic: a))
        view.beginInlineEdit(on: view.element(forTopic: a)!)
        view.inlineEditor?.stringValue = "One"
        command(view, #selector(NSResponder.insertNewline(_:)))   // finish, stay on A
        XCTAssertTrue(view.selectedElement?.topic === a)
        view.keyDown(with: key("\r"))                             // selected → sibling, editing
        view.inlineEditor?.stringValue = "Two"
        command(view, #selector(NSResponder.insertNewline(_:)))   // finish
        XCTAssertEqual(root.children.map(\.text), ["One", "Two"])
    }

    // MARK: - Delegate guards

    func testUnhandledCommandReturnsFalse() {
        let (view, _, a) = makeView()
        startEditing(view, a)
        XCTAssertFalse(command(view, #selector(NSResponder.moveLeft(_:))))
    }

    func testCommandIgnoredWhenControlIsNotTheInlineEditor() {
        let (view, _, a) = makeView()
        startEditing(view, a)
        let stranger = NSTextField()
        XCTAssertFalse(view.control(stranger, textView: NSTextView(),
                                    doCommandBy: #selector(NSResponder.insertNewline(_:))))
    }

    private func key(_ chars: String, _ mods: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars,
                         isARepeat: false, keyCode: 0)!
    }
}
