import XCTest
import AppKit
import KepModel
@testable import KepMindMap

@MainActor
final class EmoticonTests: XCTestCase {

    func testKnownNamesMapToSpecificSymbols() {
        XCTAssertEqual(MindMapEmoticon.sfSymbolName(for: "bell"), "bell")
        XCTAssertEqual(MindMapEmoticon.sfSymbolName(for: "star"), "star.fill")
        XCTAssertEqual(MindMapEmoticon.sfSymbolName(for: "warning"), "exclamationmark.triangle.fill")
    }

    func testCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(MindMapEmoticon.sfSymbolName(for: "  STAR "), "star.fill")
    }

    func testUnknownNameFallsBackToTag() {
        XCTAssertEqual(MindMapEmoticon.sfSymbolName(for: "definitely-not-a-real-emoticon"), "tag")
    }

    func testEmptyNameReturnsNil() {
        XCTAssertNil(MindMapEmoticon.sfSymbolName(for: ""))
        XCTAssertNil(MindMapEmoticon.sfSymbolName(for: "   "))
    }

    func testElementEmoticonNameMirrorsAttribute() {
        let topic = Topic(text: "x")
        let el = MindMapElement.build(from: topic)
        XCTAssertNil(el.emoticonName)
        XCTAssertEqual(el.emoticonLeadingWidth, 0)

        topic.setAttribute(TopicAttribute.emoticon, "bell")
        XCTAssertEqual(el.emoticonName, "bell")
        XCTAssertGreaterThan(el.emoticonLeadingWidth, 0)
    }

    func testImageReturnsNonNilForKnownName() {
        let img = MindMapEmoticon.image(for: "star", pointSize: 14, color: .black)
        XCTAssertNotNil(img)
        XCTAssertGreaterThan(img?.size.width ?? 0, 0)
    }
}
