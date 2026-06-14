import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Real-event coverage of the remaining single-key commands that flow through
/// performKeyEquivalent → keyDown: collapse/expand (-, =, +), ⌘D duplicate,
/// F2 edit, ⌥Space jump-to-root, and Delete. These were previously only
/// exercised by direct method calls.
@MainActor
final class MindMapInteractiveKeyCommandTests: XCTestCase {

    private func build() throws -> (WindowedMindMap, Topic, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A")
        let a1 = a.addChild(text: "A1")
        let h = WindowedMindMap(map: map)
        h.view.selectElement(h.view.element(forTopic: root))
        h.view.beginInlineEdit(on: h.view.element(forTopic: root)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        try XCTSkipIf(!ok, "headless host can't host a field editor")
        return (h, root, a, a1)
    }

    // MARK: - Collapse / expand

    func testMinusCollapsesAndPlusExpands() throws {
        let (h, _, a, _) = try build()
        h.view.selectElement(h.view.element(forTopic: a))
        h.sendKey("-")
        XCTAssertEqual(a.attribute(TopicAttribute.collapsed), "true", "minus collapses")
        h.sendKey("=")
        XCTAssertNil(a.attribute(TopicAttribute.collapsed), "equals expands")
        h.sendKey("-")
        XCTAssertEqual(a.attribute(TopicAttribute.collapsed), "true")
        h.sendKey("+")
        XCTAssertNil(a.attribute(TopicAttribute.collapsed), "plus expands")
    }

    // MARK: - ⌘D duplicate

    func testCmdDDuplicatesSubtree() throws {
        let (h, root, a, _) = try build()
        h.view.selectElement(h.view.element(forTopic: a))
        let before = root.children.count
        let handled = h.sendKeyEquivalent("d", [.command])
        XCTAssertTrue(handled, "⌘D handled")
        XCTAssertEqual(root.children.count, before + 1, "a duplicate sibling was created")
        // The clone carries the subtree (A had a child A1).
        let clone = root.children.last
        XCTAssertEqual(clone?.text, "A")
        XCTAssertEqual(clone?.children.first?.text, "A1", "deep clone includes children")
    }

    // MARK: - F2 edits the selected node

    func testF2EntersEditMode() throws {
        let (h, _, a, _) = try build()
        h.view.selectElement(h.view.element(forTopic: a))
        h.sendKey(String(Character(UnicodeScalar(0xF705)!)))   // NSF2FunctionKey
        XCTAssertNotNil(h.view.inlineEditor, "F2 opens the editor")
        XCTAssertTrue(h.view.inlineEditTarget === a)
        XCTAssertEqual(h.editorText, "A")
    }

    // MARK: - ⌥Space jumps to root

    func testOptionSpaceJumpsToRoot() throws {
        let (h, root, a, a1) = try build()
        h.view.selectElement(h.view.element(forTopic: a1))
        XCTAssertTrue(h.view.selectedElement?.topic === a1)
        h.sendKey(" ", [.option])
        XCTAssertTrue(h.view.selectedElement?.topic === root, "⌥Space selects the root")
        _ = a
    }

    // MARK: - Delete removes the selected node

    func testDeleteRemovesSelectedAndKeepsKeyboardLive() throws {
        let (h, root, a, _) = try build()
        let b = root.addChild(text: "B")
        h.view.rebuildElementsPublic()
        h.view.selectElement(h.view.element(forTopic: b))
        h.sendKey("\u{7F}")
        XCTAssertEqual(root.children.map(\.text), ["A"], "B deleted")
        XCTAssertTrue(h.view.selectedElement?.topic === root, "selection falls back to parent")
        // Keyboard still works.
        h.sendArrow(NSRightArrowFunctionKey)
        XCTAssertTrue(h.view.selectedElement?.topic === a)
    }

    // MARK: - Collapse key does NOT fire while editing (goes to the field)

    func testMinusWhileEditingTypesIntoFieldNotCollapse() throws {
        let (h, _, a, _) = try build()
        h.click(topic: a, clickCount: 2)        // edit A
        h.sendKey("x"); h.sendKey("-"); h.sendKey("y")
        XCTAssertEqual(h.editorText, "x-y", "'-' is a literal character while editing")
        XCTAssertNil(a.attribute(TopicAttribute.collapsed), "no collapse happened")
    }
}
