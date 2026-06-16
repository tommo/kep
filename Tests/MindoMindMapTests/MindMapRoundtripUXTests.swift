import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// The full mind-map editing round-trip a real user performs, driven by real
/// key events end to end: build a tree, navigate it, delete a node, re-add
/// one, reparent it, then undo/redo — checking structure, selection, AND
/// layout stability at every step.
///
/// Two regressions this pins down:
///  1. Deleting a node used to recentre the whole canvas, so the entire graph
///     (root included) jumped. The root must now stay anchored — only the
///     changed branch reflows.
///  2. Deleting a node used to move the cursor up to the PARENT. It must stay
///     at the current level (the adjacent sibling).
@MainActor
final class MindMapRoundtripUXTests: XCTestCase {

    private func tree(_ t: Topic, _ depth: Int = 0) -> String {
        var s = String(repeating: "  ", count: depth) + t.text + "\n"
        for c in t.children { s += tree(c, depth + 1) }
        return s
    }

    /// Root ─ A(A1,A2) ─ B ─ C, all on the right so arrow nav is deterministic.
    private func build() throws -> (WindowedMindMap, UndoManager, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        for name in ["A", "B", "C"] {
            let n = root.addChild(text: name)
            n.setAttribute(TopicAttribute.leftSide, "false")
        }
        let a = root.children[0]
        a.addChild(text: "A1"); a.addChild(text: "A2")

        let h = WindowedMindMap(map: map)
        let mgr = UndoManager(); mgr.groupsByEvent = false
        h.view.injectedUndoManager = mgr
        // Field-editor availability probe.
        h.view.selectElement(h.view.element(forTopic: root))
        h.view.beginInlineEdit(on: h.view.element(forTopic: root)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        try XCTSkipIf(!ok, "headless host can't host a field editor")
        return (h, mgr, root)
    }

    private func type(_ h: WindowedMindMap, _ s: String) { for ch in s { h.sendKey(String(ch)) } }
    private func sel(_ h: WindowedMindMap) -> Topic? { h.view.selectedElement?.topic }

    func testFullRoundtrip() throws {
        let (h, mgr, root) = try build()
        let a = root.children[0], b = root.children[1], c = root.children[2]

        // ── Navigate: Right INTO children is position-based (nearest by Y),
        //    Down/Up steps through same-side siblings by order ───────────────
        h.view.selectElement(h.view.element(forTopic: root))
        h.sendArrow(NSRightArrowFunctionKey)
        let rootY = h.view.element(forTopic: root)!.frame.midY
        let nearest = [a, b, c].min {
            abs(h.view.element(forTopic: $0)!.frame.midY - rootY)
                < abs(h.view.element(forTopic: $1)!.frame.midY - rootY)
        }
        XCTAssertTrue(sel(h) === nearest, "Right from root lands on the vertically-nearest child")
        h.view.selectElement(h.view.element(forTopic: a))
        h.sendArrow(NSDownArrowFunctionKey)
        XCTAssertTrue(sel(h) === b, "Down moves to sibling B")
        h.sendArrow(NSDownArrowFunctionKey)
        XCTAssertTrue(sel(h) === c, "Down moves to sibling C")

        // ── Delete B (a MIDDLE sibling) ─────────────────────────────────────
        let rootBefore = h.view.element(forTopic: root)!.frame
        h.view.selectElement(h.view.element(forTopic: b))
        h.sendKey("\u{7F}")

        // (1) layout anchor: the root must not have moved.
        let rootAfter = h.view.element(forTopic: root)!.frame
        XCTAssertEqual(rootBefore.midX, rootAfter.midX, accuracy: 0.5,
                       "root stays put horizontally when a branch is deleted")
        XCTAssertEqual(rootBefore.midY, rootAfter.midY, accuracy: 0.5,
                       "root stays put vertically when a branch is deleted")
        // (2) cursor stays at the current level → the sibling after B, i.e. C.
        XCTAssertTrue(sel(h) === c, "after deleting B the cursor moves to sibling C, not the parent")
        XCTAssertEqual(root.children.map(\.text), ["A", "C"], "B removed")

        // ── Re-add: Return on C makes a following sibling, type "D" ─────────
        h.sendKey("\r")
        type(h, "D")
        h.sendKey("\r")
        XCTAssertEqual(root.children.map(\.text), ["A", "C", "D"], "D added at the same level")
        let d = root.children[2]

        // ── Reparent: ⌘→ indents D under its preceding sibling C ────────────
        h.view.selectElement(h.view.element(forTopic: d))
        h.sendArrowEquivalent(NSRightArrowFunctionKey, [.command])
        XCTAssertTrue(d.parent === c, "⌘→ reparented D under C")
        XCTAssertEqual(root.children.map(\.text), ["A", "C"], "D left root's direct children")

        // ── Undo the reparent → D back under root ───────────────────────────
        mgr.undo()
        XCTAssertTrue(d.parent === root, "undo restored D to the root")
        XCTAssertEqual(root.children.map(\.text), ["A", "C", "D"])

        // ── Redo the reparent → D back under C ──────────────────────────────
        mgr.redo()
        XCTAssertTrue(d.parent === c, "redo re-applied the reparent")

        _ = a
    }

    /// Deleting the LAST sibling falls back to the previous sibling (still the
    /// current level), and deleting an only-child falls back to the parent.
    func testDeleteSelectionFallbacks() throws {
        let (h, _, root) = try build()
        let a = root.children[0], c = root.children[2]

        // Delete C (the last sibling) → selection goes to B (the one before).
        h.view.selectElement(h.view.element(forTopic: c))
        h.sendKey("\u{7F}")
        XCTAssertTrue(sel(h) === root.children[1], "deleting the last sibling selects the previous one")
        XCTAssertEqual(root.children.map(\.text), ["A", "B"])

        // Delete A1 then A2 (A's only children) → selection falls back to A.
        let a1 = a.children[0]
        h.view.selectElement(h.view.element(forTopic: a1))
        h.sendKey("\u{7F}")                 // A still has A2
        XCTAssertTrue(sel(h) === a.children[0], "sibling A2 selected")
        h.sendKey("\u{7F}")                 // now A is childless
        XCTAssertTrue(sel(h) === a, "deleting the only remaining child falls back to the parent")
    }

    /// Anchoring must survive several edits in a row — root stable across a
    /// delete, an add, and a reparent.
    func testRootStaysAnchoredAcrossManyEdits() throws {
        let (h, _, root) = try build()
        let origin = h.view.element(forTopic: root)!.frame

        func rootMoved() -> CGFloat {
            let f = h.view.element(forTopic: root)!.frame
            return max(abs(f.midX - origin.midX), abs(f.midY - origin.midY))
        }

        h.view.selectElement(h.view.element(forTopic: root.children[1]))
        h.sendKey("\u{7F}")                                   // delete B
        XCTAssertLessThan(rootMoved(), 0.5, "root anchored after delete")

        h.view.selectElement(h.view.element(forTopic: root.children.last!))
        h.sendKey("\r"); type(h, "Z"); h.sendKey("\r")        // add Z
        XCTAssertLessThan(rootMoved(), 0.5, "root anchored after add")

        h.view.selectElement(h.view.element(forTopic: root.children.last!))
        h.sendArrowEquivalent(NSRightArrowFunctionKey, [.command])  // indent Z
        XCTAssertLessThan(rootMoved(), 0.5, "root anchored after reparent")
    }
}
