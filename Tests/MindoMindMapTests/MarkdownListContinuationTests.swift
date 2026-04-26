import XCTest
@testable import MindoMarkdown

final class MarkdownListContinuationTests: XCTestCase {

    func testDashBulletContinues() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "- foo"), .insert("- "))
    }

    func testStarBulletContinues() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "* foo"), .insert("* "))
    }

    func testPlusBulletContinues() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "+ foo"), .insert("+ "))
    }

    func testNumericMarkerIncrements() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "3. third"), .insert("4. "))
    }

    func testNumericMarkerDoubleDigit() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "10. ten"), .insert("11. "))
    }

    func testIndentPreserved() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "  - inner"), .insert("  - "))
    }

    func testTabIndentPreserved() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "\t- inner"), .insert("\t- "))
    }

    func testEmptyMarkerBreaksOut() {
        // "- " (just the marker, no body) signals "I'm done with this list"
        XCTAssertEqual(MarkdownListContinuation.action(for: "- "), .clearMarker)
    }

    func testEmptyNumericMarkerBreaksOut() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "1. "), .clearMarker)
    }

    func testNonListLineFallsThrough() {
        XCTAssertNil(MarkdownListContinuation.action(for: "plain text"))
    }

    func testEmptyLineFallsThrough() {
        XCTAssertNil(MarkdownListContinuation.action(for: ""))
    }

    func testDashWithoutSpaceIsNotMarker() {
        // "-foo" isn't a markdown bullet; needs "- " (marker + space).
        XCTAssertNil(MarkdownListContinuation.action(for: "-foo"))
    }

    func testNumericWithoutSpaceIsNotMarker() {
        XCTAssertNil(MarkdownListContinuation.action(for: "1.foo"))
    }
}
