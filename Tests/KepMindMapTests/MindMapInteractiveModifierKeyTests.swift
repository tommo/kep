import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// Real-event coverage of the modifier-key gestures: Shift+arrow extends the
/// multi-selection (keyDown path) and ⌘+arrow moves/reorders/indents the
/// selected topic (performKeyEquivalent path — where NSApplication routes
/// key equivalents).
@MainActor
final class MindMapInteractiveModifierKeyTests: XCTestCase {

    /// Root ─ A ─ A1, A2
    ///      ─ B
    /// (all right-side, since the children are added under a right-side branch)
    private func build() throws -> (WindowedMindMap, Topic, Topic, Topic, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A"); a.setAttribute(TopicAttribute.leftSide, "false")
        let a1 = a.addChild(text: "A1"); let a2 = a.addChild(text: "A2")
        let b = root.addChild(text: "B"); b.setAttribute(TopicAttribute.leftSide, "false")
        let h = WindowedMindMap(map: map)
        // field-editor availability probe
        h.view.selectElement(h.view.element(forTopic: root))
        h.view.beginInlineEdit(on: h.view.element(forTopic: root)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        try XCTSkipIf(!ok, "headless host can't host a field editor")
        return (h, root, a, a1, a2, b)
    }

    // MARK: - Shift+arrow extends the selection

    func testShiftRightExtendsSelectionToChild() throws {
        let (h, _, a, a1, _, _) = try build()
        h.view.selectElement(h.view.element(forTopic: a))
        XCTAssertEqual(h.view.selectedTopics.count, 1)
        h.sendArrow(NSRightArrowFunctionKey, [.shift])     // extend into A1
        XCTAssertTrue(h.view.selectedTopics.contains(ObjectIdentifier(a)),  "A stays selected")
        XCTAssertTrue(h.view.selectedTopics.contains(ObjectIdentifier(a1)), "A1 added to selection")
        XCTAssertEqual(h.view.selectedTopics.count, 2)
    }

    func testShiftDownExtendsAcrossSiblings() throws {
        let (h, _, a, _, _, b) = try build()
        h.view.selectElement(h.view.element(forTopic: a))
        // Down is spatial now, so extending from A walks down through A's own
        // children before reaching sibling B — repeated Shift+Down must be able
        // to extend the selection across the subtree boundary to B (keeping A).
        var steps = 0
        while !h.view.selectedTopics.contains(ObjectIdentifier(b)) && steps < 10 {
            h.sendArrow(NSDownArrowFunctionKey, [.shift]); steps += 1
        }
        XCTAssertTrue(h.view.selectedTopics.contains(ObjectIdentifier(a)), "anchor A stays selected")
        XCTAssertTrue(h.view.selectedTopics.contains(ObjectIdentifier(b)), "extended down to B")
    }

    // MARK: - ⌘+arrow reorders / indents (performKeyEquivalent path)

    func testCmdDownReordersSiblingDown() throws {
        let (h, _, a, a1, a2, _) = try build()
        XCTAssertEqual(a.children.map(\.text), ["A1", "A2"])
        h.view.selectElement(h.view.element(forTopic: a1))
        let handled = h.sendArrowEquivalent(NSDownArrowFunctionKey, [.command])
        XCTAssertTrue(handled, "⌘↓ is handled by performKeyEquivalent")
        XCTAssertEqual(a.children.map(\.text), ["A2", "A1"], "A1 moved after A2")
        _ = a2
    }

    func testCmdUpReordersSiblingUp() throws {
        let (h, _, a, _, a2, _) = try build()
        h.view.selectElement(h.view.element(forTopic: a2))
        h.sendArrowEquivalent(NSUpArrowFunctionKey, [.command])
        XCTAssertEqual(a.children.map(\.text), ["A2", "A1"], "A2 moved before A1")
    }

    func testCmdRightIndentsUnderPrecedingSibling() throws {
        let (h, _, a, a1, a2, _) = try build()
        // A2 indents under its preceding sibling A1.
        h.view.selectElement(h.view.element(forTopic: a2))
        h.sendArrowEquivalent(NSRightArrowFunctionKey, [.command])
        XCTAssertEqual(a.children.map(\.text), ["A1"], "A2 left A's direct children")
        XCTAssertTrue(a2.parent === a1, "A2 is now a child of A1")
        _ = a
    }

    func testCmdLeftOutdentsToGrandparent() throws {
        let (h, root, a, a1, _, _) = try build()
        // A1 outdents to become a sibling of A (child of root), right after A.
        h.view.selectElement(h.view.element(forTopic: a1))
        h.sendArrowEquivalent(NSLeftArrowFunctionKey, [.command])
        XCTAssertTrue(a1.parent === root, "A1 moved up to root")
        guard let idxA = root.children.firstIndex(where: { $0 === a }),
              let idxA1 = root.children.firstIndex(where: { $0 === a1 }) else {
            return XCTFail("A and A1 should both be direct children of root")
        }
        XCTAssertEqual(idxA1, idxA + 1, "A1 sits right after A")
    }
}
