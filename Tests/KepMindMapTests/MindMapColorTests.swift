import XCTest
import AppKit
import KepModel
@testable import KepMindMap

@MainActor
final class MindMapColorTests: XCTestCase {

    func testParsesHashHexRGB() {
        guard let c = MindMapColor.parse("#FF0080") else { XCTFail(); return }
        XCTAssertEqual(c.redComponent, 1.0, accuracy: 0.001)
        XCTAssertEqual(c.greenComponent, 0.0, accuracy: 0.001)
        XCTAssertEqual(c.blueComponent, 128.0 / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.alphaComponent, 1.0, accuracy: 0.001)
    }

    func testParsesShortHexExpands() {
        // #ABC → #AABBCC
        guard let c = MindMapColor.parse("#abc") else { XCTFail(); return }
        XCTAssertEqual(c.redComponent, 0xAA / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.greenComponent, 0xBB / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.blueComponent, 0xCC / 255.0, accuracy: 0.001)
    }

    func testParsesHexWithAlpha() {
        guard let c = MindMapColor.parse("#80808080") else { XCTFail(); return }
        XCTAssertEqual(c.alphaComponent, 128.0 / 255.0, accuracy: 0.01)
    }

    func testParsesJavaFXStyle0xPrefix() {
        // JavaFX Color.toString() emits 0xRRGGBBAA — compatibility with files
        // produced by mindolph that round-tripped through Java.
        guard let c = MindMapColor.parse("0x123456FF") else { XCTFail(); return }
        XCTAssertEqual(c.redComponent, CGFloat(0x12) / 255.0, accuracy: 0.001)
    }

    func testReturnsNilOnMalformed() {
        XCTAssertNil(MindMapColor.parse(""))
        XCTAssertNil(MindMapColor.parse("not-a-color"))
        XCTAssertNil(MindMapColor.parse("#GGHHII"))
        XCTAssertNil(MindMapColor.parse("#1234567"))   // wrong length
        XCTAssertNil(MindMapColor.parse(nil))
    }

    func testWritesHashHexUppercase() {
        let c = NSColor(srgbRed: 1.0, green: 0.0, blue: 128.0 / 255.0, alpha: 1.0)
        XCTAssertEqual(MindMapColor.write(c), "#FF0080")
    }

    func testWritesIncludesAlphaWhenLessThanOne() {
        let c = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.5)
        // 0.5 * 255 = 127.5 → rounds to 128 = 0x80
        XCTAssertEqual(MindMapColor.write(c), "#FFFFFF80")
    }

    func testRoundTripsThroughParseAndWrite() {
        let original = "#7AA3E5"
        guard let parsed = MindMapColor.parse(original) else { XCTFail(); return }
        XCTAssertEqual(MindMapColor.write(parsed), original)
    }

    func testElementCustomColorsReadFromAttributes() {
        let topic = Topic(text: "Hello")
        topic.setAttribute(TopicAttribute.fillColor, "#FF0000")
        topic.setAttribute(TopicAttribute.textColor, "#00FF00")
        let el = MindMapElement.build(from: topic)
        XCTAssertNotNil(el.customFillColor)
        XCTAssertNotNil(el.customTextColor)
        XCTAssertNil(el.customBorderColor)
    }
}
