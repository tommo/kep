import XCTest
import AppKit
import KepModel
@testable import KepMindMap

@MainActor
final class ExtrasIconTests: XCTestCase {

    private func laidOutElement(text: String, extras: [any Extra]) -> MindMapElement {
        let topic = Topic(text: text)
        for e in extras { topic.setExtra(e) }
        let element = MindMapElement.build(from: topic)
        let layout = MindMapLayout(theme: .light)
        _ = layout.layout(element)
        return element
    }

    func testVisibleExtrasOrderedConsistently() {
        let topic = Topic(text: "x")
        topic.setExtra(ExtraFile(uri: "/tmp/a"))
        topic.setExtra(ExtraNote(text: "n"))
        topic.setExtra(ExtraLink(uri: "https://example.com"))
        let el = MindMapElement.build(from: topic)
        XCTAssertEqual(el.visibleExtras, [.note, .link, .file])
    }

    func testExtraStripWidthGrowsWithCount() {
        let none = laidOutElement(text: "no extras", extras: [])
        let one  = laidOutElement(text: "no extras", extras: [ExtraNote(text: "x")])
        let two  = laidOutElement(text: "no extras", extras: [ExtraNote(text: "x"), ExtraLink(uri: "https://x")])
        XCTAssertEqual(none.extraIconStripWidth, 0)
        XCTAssertGreaterThan(one.extraIconStripWidth, 0)
        XCTAssertGreaterThan(two.extraIconStripWidth, one.extraIconStripWidth)
        XCTAssertGreaterThan(two.elementSize.width, one.elementSize.width)
    }

    func testIconRectsStayInsideTopicFrame() {
        let element = laidOutElement(
            text: "hello",
            extras: [ExtraNote(text: "n"), ExtraLink(uri: "https://x"), ExtraFile(uri: "/tmp/a")]
        )
        XCTAssertEqual(element.extraIconRects.count, 3)
        for (_, rect) in element.extraIconRects {
            XCTAssertTrue(element.frame.insetBy(dx: -1, dy: -1).contains(rect),
                          "icon \(rect) should sit inside topic frame \(element.frame)")
        }
    }
}
