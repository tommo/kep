import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Coverage of the "while editing, Return/Tab commits and creates the next
/// topic" outlining flow (XMind/MindNode parity), exercised through the real
/// NSTextFieldDelegate command path on a headless view.
@MainActor
final class MindMapEditCreateFlowTests: XCTestCase {

    private func makeView() -> (MindMapView, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let a = root.addChild(text: "A")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        return (view, root, a)
    }

    /// Send a field-editor command to the view's inline-edit delegate.
    @discardableResult
    private func command(_ view: MindMapView, _ selector: Selector) -> Bool {
        guard let field = view.inlineEditor else { return false }
        return view.control(field, textView: NSTextView(), doCommandBy: selector)
    }

    private func startEditing(_ view: MindMapView, _ topic: Topic) {
        view.selectElement(view.element(forTopic: topic))
        view.beginInlineEdit(on: view.element(forTopic: topic)!)
    }

    // MARK: - Return → commit + sibling

    func testReturnWhileEditingCommitsAndCreatesSibling() {
        let (view, root, a) = makeView()
        startEditing(view, a)
        view.inlineEditor?.stringValue = "Apple"
        let handled = command(view, #selector(NSResponder.insertNewline(_:)))
        XCTAssertTrue(handled)
        XCTAssertEqual(a.text, "Apple", "the edited topic committed")
        XCTAssertEqual(root.children.count, 2, "a sibling was created")
        XCTAssertTrue(root.children[1] === view.inlineEditTarget, "the new sibling is now being edited")
        XCTAssertNotNil(view.inlineEditor, "editor reopened on the new sibling")
    }

    // MARK: - Tab → commit + child

    func testTabWhileEditingCommitsAndCreatesChild() {
        let (view, _, a) = makeView()
        startEditing(view, a)
        view.inlineEditor?.stringValue = "Parent"
        let handled = command(view, #selector(NSResponder.insertTab(_:)))
        XCTAssertTrue(handled)
        XCTAssertEqual(a.text, "Parent")
        XCTAssertEqual(a.children.count, 1, "a child was created under the edited topic")
        XCTAssertTrue(a.children[0] === view.inlineEditTarget)
        XCTAssertNotNil(view.inlineEditor)
    }

    // MARK: - Shift-Tab → commit only

    func testShiftTabCommitsWithoutCreating() {
        let (view, root, a) = makeView()
        startEditing(view, a)
        view.inlineEditor?.stringValue = "Done"
        let handled = command(view, #selector(NSResponder.insertBacktab(_:)))
        XCTAssertTrue(handled)
        XCTAssertEqual(a.text, "Done")
        XCTAssertEqual(root.children.count, 1, "no new node")
        XCTAssertNil(view.inlineEditor, "editor closed")
    }

    // MARK: - Esc → cancel

    func testEscCancelsAndKeepsOriginalText() {
        let (view, root, a) = makeView()
        startEditing(view, a)
        view.inlineEditor?.stringValue = "throwaway"
        let handled = command(view, #selector(NSResponder.cancelOperation(_:)))
        XCTAssertTrue(handled)
        XCTAssertEqual(a.text, "A", "Esc discards the edit")
        XCTAssertEqual(root.children.count, 1)
        XCTAssertNil(view.inlineEditor)
    }

    // MARK: - Chained outlining

    func testChainedReturnsBuildSiblingList() {
        // Edit A → "One", Return → sibling "Two", Return → sibling "Three".
        let (view, root, a) = makeView()
        startEditing(view, a)
        view.inlineEditor?.stringValue = "One"
        command(view, #selector(NSResponder.insertNewline(_:)))
        view.inlineEditor?.stringValue = "Two"
        command(view, #selector(NSResponder.insertNewline(_:)))
        view.inlineEditor?.stringValue = "Three"
        command(view, #selector(NSResponder.insertNewline(_:)))
        // Close the dangling editor (empty "Topic" sibling) by cancelling.
        view.cancelInlineEdit()
        XCTAssertEqual(root.children.prefix(3).map(\.text), ["One", "Two", "Three"])
    }

    // MARK: - Unrelated commands fall through

    func testUnhandledCommandReturnsFalse() {
        let (view, _, a) = makeView()
        startEditing(view, a)
        let handled = command(view, #selector(NSResponder.moveLeft(_:)))
        XCTAssertFalse(handled, "non-create commands are left to the field editor")
    }

    func testCommandIgnoredWhenControlIsNotTheInlineEditor() {
        let (view, _, a) = makeView()
        startEditing(view, a)
        // A different control must not drive the canvas.
        let stranger = NSTextField()
        let handled = view.control(stranger, textView: NSTextView(),
                                   doCommandBy: #selector(NSResponder.insertNewline(_:)))
        XCTAssertFalse(handled)
    }
}
