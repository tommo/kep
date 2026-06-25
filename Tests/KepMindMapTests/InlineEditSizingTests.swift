import XCTest
import AppKit
import KepModel
@testable import KepMindMap

final class InlineEditSizingTests: XCTestCase {
    private let font = NSFont.systemFont(ofSize: 14)
    private let insets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

    func testGrowsWithLongerText() {
        let short = InlineEditSizing.fittingSize(text: "Hi", font: font, insets: insets)
        let long = InlineEditSizing.fittingSize(
            text: "A considerably longer topic title", font: font, insets: insets)
        XCTAssertGreaterThan(long.width, short.width, "wider text → wider editor")
    }

    func testRespectsMinimums() {
        let tiny = InlineEditSizing.fittingSize(text: "", font: font, insets: insets)
        XCTAssertGreaterThanOrEqual(tiny.width, 40)
        XCTAssertGreaterThanOrEqual(tiny.height, 28)
    }

    func testWrapsAndGrowsTallBeyondMaxWidth() {
        let veryLong = String(repeating: "word ", count: 60)
        let s = InlineEditSizing.fittingSize(text: veryLong, font: font, insets: insets, maxWidth: 200)
        XCTAssertLessThanOrEqual(s.width, 200 + insets.left + insets.right + 12 + 0.5)
        XCTAssertGreaterThan(s.height, 28, "wrapped text grows in height")
    }
}

@MainActor
final class RightDragLinkTests: XCTestCase {
    func testRightDragFromAtoBCreatesJumpLink() {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A")
        let b = root.addChild(text: "B")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let elA = view.element(forTopic: a)!
        let elB = view.element(forTopic: b)!

        let made = view.completeLinkDrag(from: elA, at: CGPoint(x: elB.frame.midX, y: elB.frame.midY))
        XCTAssertTrue(made, "dropping on a different node makes a link")
        XCTAssertNotNil(a.extra(.topic), "A gained a topic jump-link")
        XCTAssertEqual(a.extra(.topic)?.value, b.attribute(ExtraTopic.topicUidAttr),
                       "the link points at B's UID")
    }

    func testRightDragOntoEmptyOrSelfMakesNoLink() {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let elA = view.element(forTopic: a)!
        // Drop on empty canvas far away.
        XCTAssertFalse(view.completeLinkDrag(from: elA, at: CGPoint(x: 5, y: 5)))
        // Drop on itself.
        XCTAssertFalse(view.completeLinkDrag(from: elA, at: CGPoint(x: elA.frame.midX, y: elA.frame.midY)))
        XCTAssertNil(a.extra(.topic))
    }
}
