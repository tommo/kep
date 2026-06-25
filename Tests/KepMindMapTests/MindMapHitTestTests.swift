import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// The combined single-pass `hitTest(at:)` (a perf-round refactor that replaced
/// five separate full-tree traversals per mouse-move) must resolve exactly what
/// the individual hit-test methods do for the same point.
@MainActor
final class MindMapHitTestTests: XCTestCase {

    private func build() -> (MindMapView, Topic, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A"); a.setAttribute(TopicAttribute.leftSide, "false")
        a.addChild(text: "A1")   // gives A a collapsator
        let v = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 1200, height: 900))
        return (v, root, a)
    }

    /// hitTest must agree with element/elementExtra/collapseIndicator/embeddedImage
    /// at every probe point.
    private func assertAgrees(_ v: MindMapView, _ p: CGPoint, _ msg: String) {
        let hit = v.hitTest(at: p)
        XCTAssertTrue(hit.element === v.element(at: p), "element mismatch: \(msg)")
        XCTAssertEqual(hit.collapse === v.collapseIndicator(at: p), true, "collapse mismatch: \(msg)")
        XCTAssertEqual(hit.extra?.0 === v.elementExtra(at: p)?.0, true, "extra element mismatch: \(msg)")
        XCTAssertEqual(hit.extra?.1, v.elementExtra(at: p)?.1, "extra type mismatch: \(msg)")
        XCTAssertEqual(hit.image === v.embeddedImage(at: p), true, "image mismatch: \(msg)")
        XCTAssertEqual(hit.isEmptyCanvas, v.isPannableCanvas(at: p), "pannable mismatch: \(msg)")
    }

    func testHitTestMatchesIndividualProbes() {
        let (v, root, a) = build()
        let rf = v.element(forTopic: root)!.frame
        let af = v.element(forTopic: a)!.frame
        let cr = v.element(forTopic: a)!.collapseIndicatorRect!
        assertAgrees(v, CGPoint(x: rf.midX, y: rf.midY), "over root")
        assertAgrees(v, CGPoint(x: af.midX, y: af.midY), "over A")
        assertAgrees(v, CGPoint(x: cr.midX, y: cr.midY), "over A's collapsator")
        assertAgrees(v, CGPoint(x: af.maxX + 500, y: af.maxY + 500), "empty canvas")
    }
}
