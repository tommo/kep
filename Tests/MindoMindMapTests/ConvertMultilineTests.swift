import XCTest
@testable import MindoMindMap

final class ConvertMultilineTests: XCTestCase {

    func testSplitDropsEmptyAndWhitespaceOnlyLines() {
        let lines = ConvertMultiline.split("a\n\n  \nb\n")
        XCTAssertEqual(lines, ["a", "b"])
    }

    func testSplitTrimsSurroundingSpaces() {
        let lines = ConvertMultiline.split("  hello  \n  world ")
        XCTAssertEqual(lines, ["hello", "world"])
    }

    func testSplitOnSingleLineReturnsOneEntry() {
        // Caller will treat this as a no-op; the split itself returns 1.
        XCTAssertEqual(ConvertMultiline.split("just one"), ["just one"])
    }

    func testSplitOnEmptyStringReturnsEmpty() {
        XCTAssertEqual(ConvertMultiline.split(""), [])
    }

    func testSplitPreservesInternalSpaces() {
        XCTAssertEqual(ConvertMultiline.split("a b c\nd e"), ["a b c", "d e"])
    }
}
