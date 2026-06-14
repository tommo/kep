import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Real-window interaction tests targeting the "totally unstable" class of
/// bugs: focus continuity across create/commit/delete, and whether the
/// keyboard keeps working after each operation. Every keystroke goes through
/// window.sendEvent so first-responder handoff is exercised for real.
@MainActor
final class MindMapInteractiveContinuityTests: XCTestCase {

    private func make() throws -> (WindowedMindMap, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let a = root.addChild(text: "A")
        let h = WindowedMindMap(map: map)
        h.view.selectElement(h.view.element(forTopic: root))
        h.view.beginInlineEdit(on: h.view.element(forTopic: root)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        try XCTSkipIf(!ok, "headless host can't provide a field editor")
        return (h, root, a)
    }

    /// True when the inline editor's field editor currently holds keyboard
    /// focus — i.e. the user could keep typing without clicking.
    private func editorIsFirstResponder(_ h: WindowedMindMap) -> Bool {
        guard let field = h.view.inlineEditor, let editor = field.currentEditor() else { return false }
        return h.window.firstResponder === editor
    }

    // MARK: - Continuity: keep typing after Return-creates-sibling

    func testCanKeepTypingAfterReturnCreatesSibling() throws {
        let (h, root, a) = try make()
        h.view.selectElement(h.view.element(forTopic: a))
        h.sendKey("A")                       // edit A → "A"
        h.sendKey("\r")                      // commit + new sibling, editor reopened
        XCTAssertTrue(editorIsFirstResponder(h), "new sibling editor must hold focus")
        h.sendKey("B"); h.sendKey("2")       // should type straight into the new editor
        XCTAssertEqual(h.editorText, "B2", "typing flows into the new sibling without a click")
        h.view.cancelInlineEdit()
        XCTAssertEqual(root.children.count, 2)
    }

    func testCanKeepTypingAfterTabCreatesChild() throws {
        let (h, _, a) = try make()
        h.view.selectElement(h.view.element(forTopic: a))
        h.sendKey("P")
        h.sendKey("\t")                      // child, editor reopened
        XCTAssertTrue(editorIsFirstResponder(h))
        h.sendKey("C")
        XCTAssertEqual(h.editorText, "C")
    }

    // MARK: - Focus survives delete; arrows still work afterward

    func testArrowsWorkAfterDeletingViaRealKey() throws {
        let (h, root, a) = try make()
        let b = root.addChild(text: "B")
        h.view.rebuildElementsPublic()
        h.view.selectElement(h.view.element(forTopic: b))
        h.sendKey("\u{7F}")                  // Delete B → selection collapses to parent (root)
        XCTAssertTrue(h.view.selectedElement?.topic === root, "selection falls back to parent")
        XCTAssertTrue(h.window.firstResponder === h.view, "canvas keeps focus after delete")
        // Arrow nav must still function (the 'unstable' symptom would be a no-op).
        h.sendArrow(NSRightArrowFunctionKey)
        XCTAssertTrue(h.view.selectedElement?.topic === a, "Right still navigates to a child")
    }

    // MARK: - Nav then immediate edit

    func testNavigateThenTypeToEditTargetsTheNavigatedNode() throws {
        let (h, _, a) = try make()
        h.view.selectElement(h.view.element(forTopic: h.view.mindMap!.root!))
        h.sendArrow(NSRightArrowFunctionKey) // root → A
        XCTAssertTrue(h.view.selectedElement?.topic === a)
        h.sendKey("Q")                       // type-to-edit on A
        XCTAssertTrue(h.view.inlineEditTarget === a)
        XCTAssertEqual(h.editorText, "Q")
    }

    // MARK: - Editor does not leak when re-triggered

    func testRepeatedTabDoesNotStackEditors() throws {
        let (h, root, _) = try make()
        h.view.selectElement(h.view.element(forTopic: root))
        // Several create-and-edit cycles; only ONE inline editor must exist.
        for _ in 0..<4 {
            h.sendKey("\t")                  // editing the new child
            h.sendKey("x")
            // commit by Tab again creates a grandchild — but count editors.
        }
        let editorCount = h.view.subviews.filter { $0 is InlineEditField }.count
        XCTAssertEqual(editorCount, 1, "no piled-up editor fields (bug #55 regression guard)")
        h.view.cancelInlineEdit()
        _ = root
    }
}
