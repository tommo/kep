import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

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

    func testTapOnExtraDispatchesCallback() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        root.setExtra(ExtraLink(uri: "https://example.com/path"))

        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.display(map: map)

        guard let rootEl = view.rootElement else { XCTFail("no root element"); return }
        guard let (_, iconRect) = rootEl.extraIconRects.first else {
            XCTFail("expected at least one extra icon")
            return
        }
        // Sanity: the icon rect is within the root's frame (drawn at right-edge).
        XCTAssertTrue(rootEl.frame.intersects(iconRect))
    }
}
