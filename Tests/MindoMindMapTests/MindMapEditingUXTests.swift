import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Comprehensive coverage of the XMind-style topic editing UX: new nodes
/// enter edit mode, typing on a selected topic starts editing (replacing the
/// text), and the Tab / Enter / ⇧Enter / ⌘Enter creation keys build the right
/// topology — all driven through the real keyDown path on a headless view.
@MainActor
final class MindMapEditingUXTests: XCTestCase {

    private func makeView() -> (MindMapView, Topic) {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        _ = root.addChild(text: "A")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        return (view, root)
    }

    private func keyEvent(_ chars: String, _ mods: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: mods,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: chars, charactersIgnoringModifiers: chars,
            isARepeat: false, keyCode: 0)!
    }

    private func select(_ view: MindMapView, _ topic: Topic) {
        view.selectElement(view.element(forTopic: topic))
    }

    // MARK: - isPrintable classifier

    func testIsPrintableAcceptsTextRejectsControlAndFunctionKeys() {
        XCTAssertTrue(MindMapView.isPrintable("a"))
        XCTAssertTrue(MindMapView.isPrintable("Z"))
        XCTAssertTrue(MindMapView.isPrintable("7"))
        XCTAssertTrue(MindMapView.isPrintable("é"))
        XCTAssertFalse(MindMapView.isPrintable("\t"))
        XCTAssertFalse(MindMapView.isPrintable("\r"))
        XCTAssertFalse(MindMapView.isPrintable("\u{7F}"))                       // delete
        XCTAssertFalse(MindMapView.isPrintable(String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))))
        XCTAssertFalse(MindMapView.isPrintable("ab"))                          // not single char
        XCTAssertFalse(MindMapView.isPrintable(""))
    }

    // MARK: - New node enters edit mode

    func testTabCreatesChildAndEntersEdit() {
        let (view, root) = makeView()
        select(view, root)
        view.keyDown(with: keyEvent("\t"))
        XCTAssertNotNil(view.inlineEditor, "Tab must open the inline editor on the new child")
        // The new child is the editor's target and is a child of root.
        XCTAssertTrue(view.inlineEditTarget?.parent === root)
        XCTAssertEqual(view.inlineEditor?.stringValue, "Topic")
    }

    func testEnterCreatesSiblingAndEntersEdit() {
        let (view, root) = makeView()
        let a = root.children.first!     // "A"
        select(view, a)
        view.keyDown(with: keyEvent("\r"))
        XCTAssertNotNil(view.inlineEditor)
        // Sibling of A → also a child of root, inserted right after A.
        XCTAssertTrue(view.inlineEditTarget?.parent === root)
        XCTAssertEqual(root.children.count, 2)
        XCTAssertTrue(root.children[1] === view.inlineEditTarget)
    }

    func testShiftEnterCreatesPrecedingSibling() {
        let (view, root) = makeView()
        let a = root.children.first!
        select(view, a)
        view.keyDown(with: keyEvent("\r", [.shift]))
        XCTAssertTrue(view.inlineEditTarget?.parent === root)
        XCTAssertTrue(root.children[0] === view.inlineEditTarget, "⇧Enter inserts before A")
        XCTAssertTrue(root.children[1] === a)
    }

    // MARK: - Type-to-edit

    func testTypingOnSelectedTopicStartsEditingWithThatChar() {
        let (view, root) = makeView()
        let a = root.children.first!
        select(view, a)
        XCTAssertNil(view.inlineEditor)
        view.keyDown(with: keyEvent("H"))
        XCTAssertNotNil(view.inlineEditor, "typing a letter starts editing")
        XCTAssertTrue(view.inlineEditTarget === a, "edits the SELECTED topic, not a new one")
        XCTAssertEqual(view.inlineEditor?.stringValue, "H", "field is seeded with the typed char (replaces text)")
        XCTAssertEqual(root.children.count, 1, "type-to-edit must NOT create a node")
    }

    func testTypeToEditThenCommitReplacesText() {
        let (view, root) = makeView()
        let a = root.children.first!
        select(view, a)
        view.keyDown(with: keyEvent("X"))
        view.inlineEditor?.stringValue = "Xenon"     // user finishes typing
        view.commitInlineEdit()
        XCTAssertEqual(a.text, "Xenon", "committing replaces the topic's text")
        XCTAssertNil(view.inlineEditor)
    }

    func testTypingWithCommandDoesNotStartEdit() {
        let (view, root) = makeView()
        let a = root.children.first!
        select(view, a)
        view.keyDown(with: keyEvent("c", [.command]))   // ⌘C, not "edit"
        XCTAssertNil(view.inlineEditor)
    }

    func testTypingWithNoSelectionDoesNothing() {
        let (view, _) = makeView()
        view.selectElement(nil)
        view.keyDown(with: keyEvent("H"))
        XCTAssertNil(view.inlineEditor)
    }

    func testTypingWhileAlreadyEditingDoesNotReopen() {
        let (view, root) = makeView()
        let a = root.children.first!
        select(view, a)
        view.keyDown(with: keyEvent("H"))
        let firstEditor = view.inlineEditor
        view.keyDown(with: keyEvent("i"))               // routed to the field, not a new editor
        XCTAssertTrue(view.inlineEditor === firstEditor, "second keystroke must not reopen the editor")
    }

    // MARK: - ⌘Enter parent

    func testCommandEnterInsertsParent() {
        let (view, root) = makeView()
        let a = root.children.first!
        select(view, a)
        view.keyDown(with: keyEvent("\r", [.command]))
        // A is now a child of a new topic, which is a child of root.
        XCTAssertNotNil(view.inlineEditor, "the new parent enters edit mode")
        let newParent = a.parent
        XCTAssertNotNil(newParent)
        XCTAssertFalse(newParent === root, "A's parent is the new node, not root")
        XCTAssertTrue(newParent?.parent === root, "the new node is a child of root")
        XCTAssertTrue(newParent === view.inlineEditTarget)
        XCTAssertTrue(newParent?.children.contains { $0 === a } ?? false)
    }

    func testCommandEnterOnRootIsNoOp() {
        let (view, root) = makeView()
        select(view, root)
        view.keyDown(with: keyEvent("\r", [.command]))
        XCTAssertNil(view.inlineEditor, "root has no parent to splice under")
    }

    // MARK: - commit / cancel

    func testCancelDiscardsEdit() {
        let (view, root) = makeView()
        let a = root.children.first!
        select(view, a)
        view.keyDown(with: keyEvent("Z"))
        view.inlineEditor?.stringValue = "garbage"
        view.cancelInlineEdit()
        XCTAssertEqual(a.text, "A", "cancel leaves the original text untouched")
        XCTAssertNil(view.inlineEditor)
    }

    // MARK: - Undo

    func testUndoOfAddParentRestores() {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let a = root.addChild(text: "A")
        let (view, undo) = makeHeadlessMindMapWithUndo(map: map)
        view.selectElement(view.element(forTopic: a))
        view.keyDown(with: keyEvent("\r", [.command]))
        XCTAssertFalse(a.parent === root)
        view.commitInlineEdit()      // close editor before undo
        undo.undo()
        XCTAssertTrue(a.parent === root, "undo restores A directly under root")
    }
}
