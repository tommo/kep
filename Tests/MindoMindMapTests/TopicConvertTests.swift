import XCTest
@testable import MindoMindMap

final class TopicConvertTests: XCTestCase {

    func testIsLinkURIAcceptsAbsoluteURLs() {
        XCTAssertTrue(TopicConvert.isLinkURI("https://example.com"))
        XCTAssertTrue(TopicConvert.isLinkURI("http://example.com/path?q=1"))
        XCTAssertTrue(TopicConvert.isLinkURI("file:///Users/me/x.txt"))
        XCTAssertTrue(TopicConvert.isLinkURI("mailto:a@b.com"))
        XCTAssertTrue(TopicConvert.isLinkURI("  https://example.com  ")) // trimmed
    }

    func testIsLinkURIRejectsPlainText() {
        XCTAssertFalse(TopicConvert.isLinkURI("example.com"))      // no scheme
        XCTAssertFalse(TopicConvert.isLinkURI("just a note"))      // whitespace
        XCTAssertFalse(TopicConvert.isLinkURI(""))
        XCTAssertFalse(TopicConvert.isLinkURI("see https://x.com")) // has spaces
    }

    func testMergedNoteText() {
        XCTAssertEqual(TopicConvert.mergedNoteText(existing: nil, adding: "first"), "first")
        XCTAssertEqual(TopicConvert.mergedNoteText(existing: "", adding: "first"), "first")
        XCTAssertEqual(TopicConvert.mergedNoteText(existing: "a", adding: "b"), "a\nb")
        XCTAssertEqual(TopicConvert.mergedNoteText(existing: "a", adding: "  b  "), "a\nb")
    }
}
