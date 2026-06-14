import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Real-gesture coverage of drag-to-REORDER among siblings (the insertion-gap
/// path), which the existing drag tests skip — they only reparent onto a node.
/// Same-parent reorder is where the index arithmetic is most fragile (the
/// remove-then-insert shifts every later sibling), so each case drags a node
/// into a specific gap and checks the resulting order.
@MainActor
final class MindMapInteractiveReorderTests: XCTestCase {

    /// Root with A,B,C,D as a right-side vertical stack.
    private func build() throws -> (WindowedMindMap, Topic, [Topic]) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        var kids: [Topic] = []
        for n in ["A", "B", "C", "D"] {
            let k = root.addChild(text: n)
            k.setAttribute(TopicAttribute.leftSide, "false")
            kids.append(k)
        }
        let h = WindowedMindMap(map: map, size: NSSize(width: 1000, height: 800))
        h.view.selectElement(h.view.element(forTopic: root))
        h.view.beginInlineEdit(on: h.view.element(forTopic: root)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        try XCTSkipIf(!ok, "headless host can't host a field editor")
        return (h, root, kids)
    }

    private func center(_ h: WindowedMindMap, _ t: Topic) -> CGPoint {
        let f = h.view.element(forTopic: t)!.frame
        return CGPoint(x: f.midX, y: f.midY)
    }

    /// Midpoint of the gap between two vertically-stacked siblings, on the
    /// sibling X band so the insertion indicator (not a reparent) activates.
    private func gapBetween(_ h: WindowedMindMap, _ upper: Topic, _ lower: Topic) -> CGPoint {
        let u = h.view.element(forTopic: upper)!.frame
        let l = h.view.element(forTopic: lower)!.frame
        return CGPoint(x: u.midX, y: (u.maxY + l.minY) / 2)
    }

    /// Dragging the TOP node DOWN into a lower gap must land it in that gap —
    /// not slide to the very end (the off-by-one when source sits before the
    /// insertion point and removal shifts later siblings down).
    func testDragTopNodeDownIntoGap() throws {
        let (h, root, k) = try build()
        let (a, b, c, d) = (k[0], k[1], k[2], k[3])
        h.drag(from: center(h, a), to: gapBetween(h, c, d), steps: 10)
        XCTAssertEqual(root.children.map(\.text), ["B", "C", "A", "D"],
                       "A dropped into the C|D gap sits between C and D")
        _ = b
    }

    /// Dragging the BOTTOM node UP into an upper gap.
    func testDragBottomNodeUpIntoGap() throws {
        let (h, root, k) = try build()
        let (a, b, c, d) = (k[0], k[1], k[2], k[3])
        h.drag(from: center(h, d), to: gapBetween(h, a, b), steps: 10)
        XCTAssertEqual(root.children.map(\.text), ["A", "D", "B", "C"],
                       "D dropped into the A|B gap sits between A and B")
        _ = c
    }

    /// The reorder must undo to the EXACT original order and redo back — the
    /// inverse uses the source's captured old index, independent of the
    /// forward off-by-one fix, so this guards both directions.
    func testDragReorderUndoRedo() throws {
        let (h, root, k) = try build()
        let mgr = UndoManager(); mgr.groupsByEvent = false
        h.view.injectedUndoManager = mgr

        h.drag(from: center(h, k[0]), to: gapBetween(h, k[2], k[3]), steps: 10)  // A → C|D gap
        XCTAssertEqual(root.children.map(\.text), ["B", "C", "A", "D"])

        mgr.undo()
        XCTAssertEqual(root.children.map(\.text), ["A", "B", "C", "D"],
                       "undo restores the exact original order")
        mgr.redo()
        XCTAssertEqual(root.children.map(\.text), ["B", "C", "A", "D"],
                       "redo re-applies the reorder")
    }

    /// A reorder must keep the root anchored (it's just another relayout).
    func testReorderKeepsRootAnchored() throws {
        let (h, root, k) = try build()
        let before = h.view.element(forTopic: root)!.frame
        h.drag(from: center(h, k[0]), to: gapBetween(h, k[2], k[3]), steps: 10)
        let after = h.view.element(forTopic: root)!.frame
        XCTAssertEqual(before.midX, after.midX, accuracy: 0.5, "root x stable across a reorder")
        XCTAssertEqual(before.midY, after.midY, accuracy: 0.5, "root y stable across a reorder")
    }
}
