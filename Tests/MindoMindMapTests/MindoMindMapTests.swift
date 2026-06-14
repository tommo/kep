import XCTest
import MindoModel
@testable import MindoMindMap

final class MindoMindMapTests: XCTestCase {

    /// Build a small tree, lay it out, and assert that elements have positive sizes
    /// and non-overlapping frames.
    func testLayoutProducesNonOverlappingElements() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "Alpha")
        let b = root.addChild(text: "Beta")
        let c = root.addChild(text: "Gamma")
        _ = a.addChild(text: "Alpha 1")
        _ = a.addChild(text: "Alpha 2")
        _ = b.addChild(text: "Beta 1")
        _ = c.addChild(text: "Gamma 1")

        let element = MindMapElement.build(from: root)
        let layout = MindMapLayout(theme: .light)
        let bounds = layout.layout(element)
        XCTAssertGreaterThan(bounds.width, 0)
        XCTAssertGreaterThan(bounds.height, 0)

        var allFrames: [CGRect] = []
        element.traverse { allFrames.append($0.frame) }
        XCTAssertEqual(allFrames.count, 8)
        for f in allFrames {
            XCTAssertGreaterThan(f.width, 0, "every element must have a positive width")
            XCTAssertGreaterThan(f.height, 0, "every element must have a positive height")
        }
        // No two element rectangles should overlap (they may touch but not intersect interior).
        for i in 0..<allFrames.count {
            for j in (i + 1)..<allFrames.count {
                let intersection = allFrames[i].insetBy(dx: 1, dy: 1).intersection(allFrames[j].insetBy(dx: 1, dy: 1))
                XCTAssertTrue(intersection.isEmpty || intersection.width < 1 || intersection.height < 1,
                              "elements \(i) and \(j) overlap: \(allFrames[i]) vs \(allFrames[j])")
            }
        }
    }

    /// Root-child side is decided by the explicit `leftSide` attribute, not
    /// auto-balanced by position: children without it all land on the right;
    /// only those stamped `leftSide=true` (creation default is right, the
    /// user drags some to the left) populate the left list.
    func testRootChildSidesFollowExplicitAttribute() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        for i in 0..<6 {
            let c = root.addChild(text: "Child \(i)")
            // Stamp two of them left, as a drag-to-left would.
            if i == 1 || i == 4 { c.setAttribute(TopicAttribute.leftSide, "true") }
        }
        let element = MindMapElement.build(from: root)
        let layout = MindMapLayout(theme: .light)
        _ = layout.layout(element)
        XCTAssertEqual(element.leftChildren.count, 2, "only the two stamped-left children go left")
        XCTAssertEqual(element.rightChildren.count, 4, "the rest stay on the right")
        XCTAssertEqual(element.leftChildren.count + element.rightChildren.count, 6)
    }

    /// With no `leftSide` attributes at all (e.g. a legacy/imported map),
    /// every root child defaults to the right — no positional alternation.
    func testRootChildrenWithoutAttributeAllGoRight() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        for i in 0..<6 { _ = root.addChild(text: "Child \(i)") }
        let element = MindMapElement.build(from: root)
        let layout = MindMapLayout(theme: .light)
        _ = layout.layout(element)
        XCTAssertTrue(element.leftChildren.isEmpty)
        XCTAssertEqual(element.rightChildren.count, 6)
    }

    /// A collapsed subtree should not contribute to layout: collapsing a parent
    /// reduces total subtree height to that parent's element height.
    func testCollapsedSubtreeShrinksLayout() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let parent = root.addChild(text: "Parent")
        for i in 0..<5 {
            _ = parent.addChild(text: "Leaf \(i)")
        }

        let expanded = MindMapElement.build(from: root)
        let expandedLayout = MindMapLayout(theme: .light)
        let expandedBounds = expandedLayout.layout(expanded)

        parent.setAttribute(TopicAttribute.collapsed, "true")
        let collapsed = MindMapElement.build(from: root)
        let collapsedLayout = MindMapLayout(theme: .light)
        let collapsedBounds = collapsedLayout.layout(collapsed)

        XCTAssertLessThan(collapsedBounds.height, expandedBounds.height,
                          "collapsing should reduce subtree height")
    }
}
