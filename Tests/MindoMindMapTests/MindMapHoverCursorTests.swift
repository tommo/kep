import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// The hover-cursor decision: empty canvas shows the open-hand "drag to pan"
/// affordance, anything interactive (a topic, its collapsator, an extra icon)
/// shows the arrow. Tests the pure hit-test composition behind the cursor.
@MainActor
final class MindMapHoverCursorTests: XCTestCase {

    private func build() -> (MindMapView, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A"); a.setAttribute(TopicAttribute.leftSide, "false")
        a.addChild(text: "A1")   // gives A a collapsator
        let v = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 1200, height: 900))
        return (v, root, a)
    }

    func testEmptyCanvasIsPannable() {
        let (v, _, a) = build()
        let f = v.element(forTopic: a)!.frame
        // Far away from any laid-out topic.
        XCTAssertTrue(v.isPannableCanvas(at: CGPoint(x: f.maxX + 400, y: f.maxY + 400)),
                      "a point clear of every node is pannable canvas")
    }

    func testOverTopicIsNotPannable() {
        let (v, root, a) = build()
        for t in [root, a] {
            let f = v.element(forTopic: t)!.frame
            XCTAssertFalse(v.isPannableCanvas(at: CGPoint(x: f.midX, y: f.midY)),
                           "the cursor over a topic box is not pannable")
        }
    }

    func testOverCollapsatorIsNotPannable() {
        let (v, _, a) = build()
        let cr = v.element(forTopic: a)!.collapseIndicatorRect!
        XCTAssertFalse(v.isPannableCanvas(at: CGPoint(x: cr.midX, y: cr.midY)),
                       "the cursor over the fold circle is not pannable (it toggles collapse)")
    }
}
