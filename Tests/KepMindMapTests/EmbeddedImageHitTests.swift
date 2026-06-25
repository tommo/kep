import XCTest
import AppKit
import KepModel
@testable import KepMindMap

@MainActor
final class EmbeddedImageHitTests: XCTestCase {

    /// 1x1 transparent PNG so we have a real NSImage in the topic without
    /// shipping a fixture file.
    private let onePixelPNG: String = {
        let raw = Data([
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
            0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
            0x08,0x06,0x00,0x00,0x00,0x1F,0x15,0xC4,
            0x89,0x00,0x00,0x00,0x0D,0x49,0x44,0x41,
            0x54,0x78,0x9C,0x62,0x00,0x01,0x00,0x00,
            0x05,0x00,0x01,0x0D,0x0A,0x2D,0xB4,0x00,
            0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,
            0x42,0x60,0x82
        ])
        return raw.base64EncodedString()
    }()

    func testEmbeddedImageHitReturnsImageInsideRect() {
        let map = MindMap()
        let root = Topic(text: "With image")
        root.setAttribute(TopicAttribute.image, onePixelPNG)
        map.root = root
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let el = view.element(forTopic: root)!
        let center = CGPoint(x: el.embeddedImageDrawRect.midX, y: el.embeddedImageDrawRect.midY)
        XCTAssertNotNil(view.embeddedImage(at: center))
    }

    func testEmbeddedImageHitReturnsNilOutsideRect() {
        let map = MindMap()
        let root = Topic(text: "With image")
        root.setAttribute(TopicAttribute.image, onePixelPNG)
        map.root = root
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let el = view.element(forTopic: root)!
        // Far-away point outside any topic's image rect.
        let outside = CGPoint(x: el.frame.maxX + 200, y: el.frame.maxY + 200)
        XCTAssertNil(view.embeddedImage(at: outside))
    }

    func testEmbeddedImageHitReturnsNilForTopicWithoutImage() {
        let map = MindMap()
        let root = Topic(text: "No image")
        map.root = root
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let el = view.element(forTopic: root)!
        XCTAssertNil(view.embeddedImage(at: CGPoint(x: el.frame.midX, y: el.frame.midY)))
    }
}
