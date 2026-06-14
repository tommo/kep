import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// GENUINE interactive UI tests: a real key NSWindow hosts the MindMapView,
/// and every keystroke is posted through `window.sendEvent` so it travels
/// the real responder chain and (while editing) the live NSTextField field
/// editor. Unlike the window-less unit tests, these prove the end-to-end
/// behavior — e.g. that typing on a fresh node actually REPLACES its "Topic"
/// placeholder in the real editor rather than appending.
@MainActor
final class MindMapInteractiveUITests: XCTestCase {

    private func make() throws -> (WindowedMindMap, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        let a = root.addChild(text: "A")
        let h = WindowedMindMap(map: map)
        // Bail clearly if this CI host can't host a key window / field editor.
        try XCTSkipIf(!windowEditorWorks(h), "headless host can't provide a field editor")
        return (h, root, a)
    }

    /// Sanity that the environment yields a live field editor when editing.
    private func windowEditorWorks(_ h: WindowedMindMap) -> Bool {
        h.view.selectElement(h.view.element(forTopic: h.view.mindMap!.root!))
        h.view.beginInlineEdit(on: h.view.element(forTopic: h.view.mindMap!.root!)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        return ok
    }

    // MARK: - Real typing into the field editor

    func testTypingOnFreshNodeReplacesPlaceholderInRealEditor() throws {
        let (h, root, _) = try make()
        h.view.selectElement(h.view.element(forTopic: root))
        h.sendKey("\t")                       // Tab → new child "Topic", editor open, text selected
        XCTAssertEqual(h.editorText, "Topic", "editor opens showing the placeholder")
        XCTAssertEqual(h.view.inlineEditor?.currentEditor()?.selectedRange,
                       NSRange(location: 0, length: 5), "placeholder is fully selected")
        h.sendKey("H")                        // replaces the whole selection
        h.sendKey("i")
        XCTAssertEqual(h.editorText, "Hi", "typing REPLACES 'Topic' (not 'TopicHi')")
    }

    func testTypeToEditOnSelectedTopicThroughRealEvents() throws {
        let (h, _, a) = try make()
        h.view.selectElement(h.view.element(forTopic: a))
        h.sendKey("X")                        // type-to-edit starts, seeded with X
        XCTAssertNotNil(h.view.inlineEditor)
        XCTAssertTrue(h.view.inlineEditTarget === a)
        h.sendKey("Y")                        // goes to the live field editor
        XCTAssertEqual(h.editorText, "XY")
    }

    // MARK: - Real arrow navigation through the responder chain

    func testArrowKeyThroughWindowMovesSelection() throws {
        let (h, root, a) = try make()
        h.view.selectElement(h.view.element(forTopic: root))
        h.sendArrow(NSRightArrowFunctionKey)
        XCTAssertTrue(h.view.selectedElement?.topic === a, "Right arrow event navigates to the child")
    }

    // MARK: - Real commit-and-create outlining via Return/Tab in the editor

    func testReturnInEditorCommitsAndStaysThroughRealEvents() throws {
        let (h, root, a) = try make()
        h.view.selectElement(h.view.element(forTopic: a))
        h.sendKey("O"); h.sendKey("n"); h.sendKey("e")   // type "One" (O replaces "A")
        XCTAssertEqual(h.editorText, "One")
        h.sendKey("\r")                                   // Return → commit + STAY
        XCTAssertEqual(a.text, "One", "committed through the real editor")
        XCTAssertEqual(root.children.count, 1, "Return while editing does NOT create a sibling")
        XCTAssertNil(h.view.inlineEditor, "edit finished")
        XCTAssertTrue(h.view.selectedElement?.topic === a, "selection stays on the edited node — no warp")
    }

    func testReturnOnSelectedTopicCreatesSiblingThroughRealEvents() throws {
        let (h, root, a) = try make()
        h.view.selectElement(h.view.element(forTopic: a))   // selected, NOT editing
        h.sendKey("\r")                                      // → new sibling, editing
        XCTAssertEqual(root.children.count, 2)
        XCTAssertNotNil(h.view.inlineEditor, "the new sibling is ready to type")
        XCTAssertTrue(h.view.inlineEditTarget?.parent === root)
    }

    func testTabOnSelectedTopicCreatesChildThroughRealEvents() throws {
        let (h, _, a) = try make()
        h.view.selectElement(h.view.element(forTopic: a))
        h.sendKey("\t")                                      // → child, editing
        XCTAssertEqual(a.children.count, 1)
        XCTAssertNotNil(h.view.inlineEditor)
    }

    // MARK: - F2 edit + Esc cancel through real events

    func testEscInEditorCancelsAndKeepsText() throws {
        let (h, _, a) = try make()
        h.view.selectElement(h.view.element(forTopic: a))
        h.sendKey("Z")                                    // start editing "Z"
        XCTAssertEqual(h.editorText, "Z")
        h.sendKey("\u{1B}")                               // Esc
        XCTAssertNil(h.view.inlineEditor, "Esc closes the editor")
        XCTAssertEqual(a.text, "A", "original text preserved")
    }
}
