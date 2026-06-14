import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// ⌘+arrow outline moves (indent / outdent / reorder) driven through the real
/// performKeyEquivalent path, focusing on the BOUNDARY and ROUND-TRIP cases the
/// existing happy-path tests skip — where index/side arithmetic bugs hide.
@MainActor
final class MindMapInteractiveOutlineMoveTests: XCTestCase {

    /// Root ─ A(right) ─ A1, A2 ─ B(right)
    private func build() throws -> (WindowedMindMap, Topic, Topic, Topic, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A"); a.setAttribute(TopicAttribute.leftSide, "false")
        let a1 = a.addChild(text: "A1"); let a2 = a.addChild(text: "A2")
        let b = root.addChild(text: "B"); b.setAttribute(TopicAttribute.leftSide, "false")
        let h = WindowedMindMap(map: map)
        let mgr = UndoManager(); mgr.groupsByEvent = false
        h.view.injectedUndoManager = mgr
        h.view.selectElement(h.view.element(forTopic: root))
        return (h, root, a, a1, a2, b)
    }
    private func side(_ h: WindowedMindMap, _ t: Topic) -> Bool {
        h.view.element(forTopic: t)!.isLeftSide
    }

    // MARK: - Boundary no-ops

    func testIndentFirstChildIsNoOp() throws {
        let (h, _, a, a1, a2, _) = try build()
        h.view.selectElement(h.view.element(forTopic: a1))   // A1 has no preceding sibling
        h.sendArrowEquivalent(NSRightArrowFunctionKey, [.command])
        XCTAssertTrue(a1.parent === a, "first child can't indent — stays put")
        XCTAssertEqual(a.children.map(\.text), ["A1", "A2"])
        _ = a2
    }

    func testOutdentRootChildIsNoOp() throws {
        let (h, root, a, _, _, _) = try build()
        h.view.selectElement(h.view.element(forTopic: a))    // parent is root, no grandparent
        h.sendArrowEquivalent(NSLeftArrowFunctionKey, [.command])
        XCTAssertTrue(a.parent === root, "a root child can't outdent — stays put")
    }

    func testReorderPastBoundaryIsNoOp() throws {
        let (h, _, a, a1, a2, _) = try build()
        h.view.selectElement(h.view.element(forTopic: a1))
        h.sendArrowEquivalent(NSUpArrowFunctionKey, [.command])     // A1 already first
        XCTAssertEqual(a.children.map(\.text), ["A1", "A2"], "first sibling can't move up")
        h.view.selectElement(h.view.element(forTopic: a2))
        h.sendArrowEquivalent(NSDownArrowFunctionKey, [.command])   // A2 already last
        XCTAssertEqual(a.children.map(\.text), ["A1", "A2"], "last sibling can't move down")
    }

    // MARK: - Indent / outdent round-trip

    func testIndentThenOutdentRoundTrips() throws {
        let (h, _, a, a1, a2, _) = try build()
        // Indent A2 under A1.
        h.view.selectElement(h.view.element(forTopic: a2))
        h.sendArrowEquivalent(NSRightArrowFunctionKey, [.command])
        XCTAssertTrue(a2.parent === a1, "A2 indented under A1")
        XCTAssertEqual(a.children.map(\.text), ["A1"])
        // Outdent A2 back — it should return to A, right after A1.
        h.sendArrowEquivalent(NSLeftArrowFunctionKey, [.command])
        XCTAssertTrue(a2.parent === a, "A2 outdented back under A")
        XCTAssertEqual(a.children.map(\.text), ["A1", "A2"], "original order restored")
    }

    // MARK: - Outdent across the root boundary preserves the visual side

    /// Outdenting A1 (under right-side A) up to the root must keep it on the
    /// RIGHT — the side it visually came from — not let balanceRoot flip it to
    /// the left by index parity. (Class of bug #39/#40.)
    func testOutdentToRootKeepsSide() throws {
        let (h, root, a, a1, _, _) = try build()
        XCTAssertFalse(side(h, a), "A starts on the right")
        h.view.selectElement(h.view.element(forTopic: a1))
        h.sendArrowEquivalent(NSLeftArrowFunctionKey, [.command])
        XCTAssertTrue(a1.parent === root, "A1 outdented to the root")
        XCTAssertFalse(side(h, a1), "A1 stays on the RIGHT after outdenting to root, no side flip")
        _ = a
    }

    // MARK: - Undo of an indent

    func testIndentIsUndoable() throws {
        let (h, _, a, _, a2, _) = try build()
        let mgr = h.view.injectedUndoManager!
        h.view.selectElement(h.view.element(forTopic: a2))
        h.sendArrowEquivalent(NSRightArrowFunctionKey, [.command])
        XCTAssertEqual(a.children.map(\.text), ["A1"])
        mgr.undo()
        XCTAssertEqual(a.children.map(\.text), ["A1", "A2"], "undo restores A2 under A")
    }
}
