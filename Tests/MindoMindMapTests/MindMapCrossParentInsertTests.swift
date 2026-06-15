import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Dragging a node onto a DIFFERENT parent should drop it at a specific gap
/// among that parent's children (insertion), like sibling reordering — not just
/// append it. Real-gesture coverage via the windowed harness.
@MainActor
final class MindMapCrossParentInsertTests: XCTestCase {

    /// root → P1[A, B], P2[C, D]; everything on the right side as a vertical stack.
    private func build() throws -> (WindowedMindMap, p1: Topic, p2: Topic, a: Topic, c: Topic, d: Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        func right(_ t: Topic) -> Topic { t.setAttribute(TopicAttribute.leftSide, "false"); return t }
        let p1 = right(root.addChild(text: "P1"))
        let a = p1.addChild(text: "A"); _ = p1.addChild(text: "B")
        let p2 = right(root.addChild(text: "P2"))
        let c = p2.addChild(text: "C"); let d = p2.addChild(text: "D")
        let h = WindowedMindMap(map: map, size: NSSize(width: 1200, height: 800))
        h.view.selectElement(h.view.element(forTopic: root))
        h.view.beginInlineEdit(on: h.view.element(forTopic: root)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        try XCTSkipIf(!ok, "headless host can't host a field editor")
        return (h, p1, p2, a, c, d)
    }

    private func center(_ h: WindowedMindMap, _ t: Topic) -> CGPoint {
        let f = h.view.element(forTopic: t)!.frame
        return CGPoint(x: f.midX, y: f.midY)
    }
    private func gapBetween(_ h: WindowedMindMap, _ upper: Topic, _ lower: Topic) -> CGPoint {
        let u = h.view.element(forTopic: upper)!.frame
        let l = h.view.element(forTopic: lower)!.frame
        return CGPoint(x: u.midX, y: (u.maxY + l.minY) / 2)
    }

    func testDragIntoAnotherParentsGapInsertsThere() throws {
        let (h, p1, p2, a, c, d) = try build()
        // Drag A (under P1) into the C|D gap (under P2).
        h.drag(from: center(h, a), to: gapBetween(h, c, d), steps: 12)
        XCTAssertEqual(p2.children.map(\.text), ["C", "A", "D"],
                       "A inserted between C and D under the new parent P2")
        XCTAssertFalse(p1.children.contains { $0 === a }, "A left its old parent P1")
        XCTAssertTrue(a.parent === p2, "A reparented to P2")
    }
}
