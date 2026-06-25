import XCTest
import AppKit
import KepModel
@testable import KepMindMap

@MainActor
final class EmbeddedImageTests: XCTestCase {

    /// Tiny 4×4 PNG checkerboard, base64-encoded. Created on the fly so the
    /// test doesn't drag along a fixture binary.
    private func makeTinyPNG() -> String {
        let size = NSSize(width: 4, height: 4)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.set()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        NSColor.white.set()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        NSRect(x: 2, y: 2, width: 2, height: 2).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return ""
        }
        return png.base64EncodedString()
    }

    func testElementDecodesEmbeddedImage() {
        let topic = Topic(text: "with image")
        topic.setAttribute(TopicAttribute.image, makeTinyPNG())
        let element = MindMapElement.build(from: topic)
        XCTAssertNotNil(element.embeddedImage, "decoded image should not be nil")
        XCTAssertGreaterThan(element.embeddedImageHeight, 0)
    }

    func testInvalidBase64ProducesNilImage() {
        let topic = Topic(text: "broken")
        topic.setAttribute(TopicAttribute.image, "<<not base64>>")
        let element = MindMapElement.build(from: topic)
        XCTAssertNil(element.embeddedImage)
        XCTAssertEqual(element.embeddedImageHeight, 0)
    }

    func testLayoutGrowsTopicForImage() {
        let plain = Topic(text: "plain")
        let withImage = Topic(text: "with image")
        withImage.setAttribute(TopicAttribute.image, makeTinyPNG())

        let plainEl = MindMapElement.build(from: plain)
        let withImageEl = MindMapElement.build(from: withImage)
        let layout = MindMapLayout(theme: .light)
        _ = layout.layout(plainEl)
        _ = layout.layout(withImageEl)

        XCTAssertGreaterThan(withImageEl.elementSize.height, plainEl.elementSize.height,
                             "topic with embedded image should be taller than plain topic")
    }

    func testDataURLPrefixIsTolerated() {
        let topic = Topic(text: "with prefix")
        topic.setAttribute(TopicAttribute.image, "data:image/png;base64,\(makeTinyPNG())")
        let element = MindMapElement.build(from: topic)
        XCTAssertNotNil(element.embeddedImage, "data: URL prefix should be stripped")
    }
}
