import XCTest
import AppKit
@testable import KepMindMap

final class TopicTextAlignTests: XCTestCase {

    func testParseLeft() {
        XCTAssertEqual(TopicTextAlign.from(attribute: "left"), .left)
        XCTAssertEqual(TopicTextAlign.from(attribute: "left").nsAlignment, .left)
    }

    func testParseCenter() {
        XCTAssertEqual(TopicTextAlign.from(attribute: "center"), .center)
        XCTAssertEqual(TopicTextAlign.from(attribute: "center").nsAlignment, .center)
    }

    func testParseRight() {
        XCTAssertEqual(TopicTextAlign.from(attribute: "right"), .right)
        XCTAssertEqual(TopicTextAlign.from(attribute: "right").nsAlignment, .right)
    }

    func testNilAttributeFallsBackToCenter() {
        // Pre-feature behaviour: every topic was centered. Absent attribute
        // must keep that default so existing maps don't shift.
        XCTAssertEqual(TopicTextAlign.from(attribute: nil), .center)
    }

    func testUnknownValueFallsBackToCenter() {
        XCTAssertEqual(TopicTextAlign.from(attribute: "diagonal"), .center)
        XCTAssertEqual(TopicTextAlign.from(attribute: ""), .center)
    }
}
