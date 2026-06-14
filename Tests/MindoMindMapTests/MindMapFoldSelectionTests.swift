import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Folding a subtree (Fold All / Fold Subtree) can hide the currently-selected
/// topic. The selection must then jump to the nearest VISIBLE ancestor — the
/// collapsed node you can still see — instead of being stranded on a hidden
/// node, where the highlight draws in the wrong place and arrow navigation
/// computes from an off-screen element.
@MainActor
final class MindMapFoldSelectionTests: XCTestCase {

    private func hasCollapsedAncestor(_ t: Topic) -> Bool {
        var p = t.parent
        while let cur = p {
            if cur.attribute(TopicAttribute.collapsed).flatMap(Bool.init) ?? false { return true }
            p = cur.parent
        }
        return false
    }

    /// root → A → A1 → A1x  (a deep single chain) + sibling B.
    private func build() -> (MindMapView, Topic, Topic, Topic, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A"); a.setAttribute(TopicAttribute.leftSide, "false")
        let a1 = a.addChild(text: "A1")
        let a1x = a1.addChild(text: "A1x")
        let b = root.addChild(text: "B"); b.setAttribute(TopicAttribute.leftSide, "false")
        let v = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 1400, height: 1000))
        return (v, root, a, a1, a1x, b)
    }

    func testFoldAllMovesSelectionOutOfHiddenSubtree() {
        let (v, _, a, _, a1x, _) = build()
        v.selectElement(v.element(forTopic: a1x))
        XCTAssertTrue(v.selectedElement?.topic === a1x, "deep node selected")

        v.setAllCollapsed(true)

        let sel = v.selectedElement?.topic
        XCTAssertNotNil(sel, "something stays selected")
        XCTAssertFalse(hasCollapsedAncestor(sel!), "the selection is on a VISIBLE node after Fold All")
        XCTAssertTrue(sel === a, "selection moved up to the highest collapsed (still-visible) ancestor A")
    }

    func testFoldSubtreeMovesSelectionToTheFoldedRoot() {
        let (v, _, a, a1, a1x, _) = build()
        v.selectElement(v.element(forTopic: a1x))
        // Fold the A subtree from the context-menu path.
        v.undoableSetSubtreeCollapsed(rootedAt: a, collapsed: true)

        let sel = v.selectedElement?.topic
        XCTAssertTrue(sel === a, "selection collapsed up to the folded subtree root A")
        XCTAssertFalse(hasCollapsedAncestor(sel!))
        _ = a1
    }

    /// Selection that is NOT hidden by the fold stays exactly where it is.
    func testFoldDoesNotDisturbAVisibleSelection() {
        let (v, _, a, _, _, b) = build()
        v.selectElement(v.element(forTopic: b))     // B is a leaf — folding A can't hide it
        v.undoableSetSubtreeCollapsed(rootedAt: a, collapsed: true)
        XCTAssertTrue(v.selectedElement?.topic === b, "a visible selection is untouched by folding elsewhere")
    }

    /// After the fixup the selected element must be the LIVE rebuilt one, so
    /// navigation works: from the folded A, Right can't descend (children
    /// hidden) and stays put; Down moves to the sibling B.
    func testNavigationWorksAfterFoldFixup() {
        let (v, _, a, _, a1x, b) = build()
        v.selectElement(v.element(forTopic: a1x))
        v.setAllCollapsed(true)
        XCTAssertTrue(v.selectedElement?.topic === a)
        v.move(.down)
        XCTAssertTrue(v.selectedElement?.topic === b, "Down from folded A navigates to sibling B")
    }
}
