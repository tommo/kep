import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// Bug #55 repro: "keep pressing Tab and you can get that shit". Tab adds
/// a child and selects it, so spamming Tab builds a deep chain of single
/// children. We dump the resulting element frames and assert on the side
/// + monotonic-x progression to see what the user is seeing.
@MainActor
final class TabSpamLayoutTests: XCTestCase {

    private func makeViewWithLeftRootChild() -> (MindMapView, root: Topic, leftA: Topic) {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        // Force a left-side root child so the chain is rooted on the left.
        let leftA = root.addChild(text: "L0")
        leftA.setAttribute(TopicAttribute.leftSide, "true")
        // Plus one right child so balanceRoot has both lists populated.
        _ = root.addChild(text: "R0")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 1200, height: 700))
        view.selectElement(view.element(forTopic: leftA))
        return (view, root, leftA)
    }

    func testTabSpamOnLeftRootChildKeepsChainOnTheLeft() {
        let (view, root, leftA) = makeViewWithLeftRootChild()
        // Press Tab 6 times → leftA gets a child, then a grandchild, etc.
        for _ in 0..<6 { view.addChild() }
        // Walk the descendant chain we just built.
        var node: Topic? = leftA
        var depth = 0
        var prevMidX: CGFloat = .greatestFiniteMagnitude
        while let n = node, let el = view.element(forTopic: n) {
            // Every link in the chain must report isLeftSide=true.
            XCTAssertTrue(el.isLeftSide, "depth \(depth) (\(n.text)) lost its leftSide flag — element x=\(el.frame.midX)")
            // X must monotonically decrease (each child sits left of its parent).
            if depth > 0 {
                XCTAssertLessThan(el.frame.midX, prevMidX,
                                  "depth \(depth) (\(n.text)) is not left of its parent: midX=\(el.frame.midX), parent midX=\(prevMidX)")
            }
            prevMidX = el.frame.midX
            depth += 1
            node = n.children.first
        }
        XCTAssertEqual(depth, 7, "expected leftA + 6 descendants")
        // Sanity: root is still in the tree.
        XCTAssertTrue(view.element(forTopic: root) != nil)
    }

    /// Bug #55: each Tab opens a new inline edit, but the previous edit
    /// was never torn down — the old NSTextFields piled up on the canvas
    /// and looked like overlapping topic boxes. After the fix there must
    /// be at most one live inline editor at any time, and the canvas's
    /// subview list must not have leaked NSTextFields.
    func testTabSpamLeavesOnlyOneInlineEditor() {
        let (view, _, _) = makeViewWithLeftRootChild()
        for _ in 0..<6 { view.addChild() }
        let editors = view.subviews.compactMap { $0 as? NSTextField }
        XCTAssertEqual(editors.count, 1, "expected exactly one inline NSTextField, found \(editors.count)")
        XCTAssertNotNil(view.inlineEditor)
    }

    /// Regression check: the cascade should NOT pile every node at the same
    /// X. Each child's frame should be strictly left of its parent by
    /// approximately element width + horizontalGap.
    func testTabSpamCascadeHasMonotonicSpacing() {
        let (view, _, leftA) = makeViewWithLeftRootChild()
        for _ in 0..<6 { view.addChild() }
        var node: Topic? = leftA
        var prevMaxX: CGFloat? = nil
        while let n = node, let el = view.element(forTopic: n) {
            if let prev = prevMaxX {
                // Child's right edge should be left of parent's left edge.
                // (A modest overlap tolerance lets us catch egregious pile-ups.)
                XCTAssertLessThanOrEqual(el.frame.maxX, prev + 4,
                                         "\(n.text) (maxX \(el.frame.maxX)) overlaps right of parent (minX \(prev))")
            }
            prevMaxX = el.frame.minX
            node = n.children.first
        }
    }
}
