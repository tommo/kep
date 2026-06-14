import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Real copy/cut/paste round-trips through the canvas responder actions
/// (`copy(_:)` / `cut(_:)` / `paste(_:)` — exactly what ⌘C/⌘X/⌘V invoke via
/// the responder chain), using the live NSPasteboard. Verifies a whole subtree
/// survives the JSON forest codec, lands under the right target, and undoes in
/// one step — the things a model-only test of the codec can't prove end to end.
@MainActor
final class MindMapInteractiveClipboardTests: XCTestCase {

    /// Root ─ Src(S1, S2(S2a)) ─ Dst
    private func build() throws -> (WindowedMindMap, UndoManager, Topic, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let src = root.addChild(text: "Src"); src.setAttribute(TopicAttribute.leftSide, "false")
        src.addChild(text: "S1")
        let s2 = src.addChild(text: "S2"); s2.addChild(text: "S2a")
        let dst = root.addChild(text: "Dst"); dst.setAttribute(TopicAttribute.leftSide, "false")

        let h = WindowedMindMap(map: map)
        let mgr = UndoManager(); mgr.groupsByEvent = false
        h.view.injectedUndoManager = mgr
        h.view.rebuildElementsPublic()
        return (h, mgr, root, src, dst)
    }

    private func tree(_ t: Topic, _ d: Int = 0) -> String {
        var s = String(repeating: "  ", count: d) + t.text + "\n"
        for c in t.children { s += tree(c, d + 1) }
        return s
    }

    // MARK: - Copy → paste replicates the whole subtree under the target

    func testCopyPasteGraftsFullSubtreeUnderTarget() throws {
        let (h, mgr, _, src, dst) = try build()

        h.view.selectElement(h.view.element(forTopic: src))
        h.view.copy(nil)                                   // ⌘C
        h.view.selectElement(h.view.element(forTopic: dst))
        h.view.paste(nil)                                  // ⌘V

        // Original Src is untouched; Dst gained a deep clone of it.
        XCTAssertEqual(src.children.map(\.text), ["S1", "S2"], "source subtree unchanged by copy")
        XCTAssertEqual(dst.children.count, 1, "one subtree pasted under Dst")
        let pasted = dst.children[0]
        XCTAssertEqual(tree(pasted), """
        Src
          S1
          S2
            S2a

        """, "the entire Src subtree (incl. grandchild) was replicated")

        // One ⌘Z removes the whole pasted subtree.
        mgr.undo()
        XCTAssertTrue(dst.children.isEmpty, "undo removes the pasted subtree in one step")
    }

    // MARK: - Cut → paste moves the subtree

    func testCutPasteMovesSubtree() throws {
        let (h, mgr, root, src, dst) = try build()

        h.view.selectElement(h.view.element(forTopic: src))
        h.view.cut(nil)                                    // ⌘X removes Src
        XCTAssertEqual(root.children.map(\.text), ["Dst"], "cut removed Src from the root")

        h.view.selectElement(h.view.element(forTopic: dst))
        h.view.paste(nil)                                  // ⌘V under Dst
        XCTAssertEqual(dst.children.map(\.text), ["Src"], "Src grafted under Dst")
        XCTAssertEqual(dst.children[0].children.map(\.text), ["S1", "S2"], "with its children")

        // Undo paste, then undo cut → back to the start.
        mgr.undo()
        XCTAssertTrue(dst.children.isEmpty, "undo removes the paste")
        mgr.undo()
        XCTAssertEqual(root.children.map(\.text), ["Src", "Dst"], "undo restores the cut subtree")
    }

    // MARK: - Paste keeps the root stable in the viewport

    /// Pasting can roughly double the content height, which (when it grows past
    /// the canvas edge) engages the clamp + scroll-compensation. Inside a real
    /// NSScrollView the root must stay fixed *relative to the viewport* — that's
    /// the no-jump invariant the user actually sees.
    func testPasteKeepsRootStableInViewport() throws {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let src = root.addChild(text: "Src"); src.setAttribute(TopicAttribute.leftSide, "false")
        src.addChild(text: "S1"); src.addChild(text: "S2").addChild(text: "S2a")
        let dst = root.addChild(text: "Dst"); dst.setAttribute(TopicAttribute.leftSide, "false")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 360))
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 500, height: 360))
        scroll.documentView = view
        view.display(map: map)

        func rootInViewport() -> CGPoint {
            let f = view.element(forTopic: root)!.frame
            let o = scroll.contentView.bounds.origin
            return CGPoint(x: f.midX - o.x, y: f.midY - o.y)
        }
        let before = rootInViewport()

        view.selectElement(view.element(forTopic: src))
        view.copy(nil)
        view.selectElement(view.element(forTopic: dst))
        view.paste(nil)

        let after = rootInViewport()
        XCTAssertEqual(before.x, after.x, accuracy: 1.5, "root holds its viewport x across paste")
        XCTAssertEqual(before.y, after.y, accuracy: 1.5, "root holds its viewport y across paste")
    }
}
