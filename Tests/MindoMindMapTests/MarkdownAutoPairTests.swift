import XCTest
@testable import MindoMarkdown

final class MarkdownAutoPairTests: XCTestCase {

    func testRoundBracketsPair() {
        XCTAssertEqual(MarkdownAutoPair.closer(for: "("), ")")
    }

    func testSquareBracketsPair() {
        XCTAssertEqual(MarkdownAutoPair.closer(for: "["), "]")
    }

    func testCurlyBracketsPair() {
        XCTAssertEqual(MarkdownAutoPair.closer(for: "{"), "}")
    }

    func testDoubleQuotePairsToItself() {
        XCTAssertEqual(MarkdownAutoPair.closer(for: "\""), "\"")
    }

    func testSingleQuotePairsToItself() {
        XCTAssertEqual(MarkdownAutoPair.closer(for: "'"), "'")
    }

    func testBacktickPairsToItself() {
        XCTAssertEqual(MarkdownAutoPair.closer(for: "`"), "`")
    }

    func testAsteriskNotPaired() {
        // Bold/italic markers would mis-pair: typing **bold** would expand
        // to * * **bold**. Skipped on purpose.
        XCTAssertNil(MarkdownAutoPair.closer(for: "*"))
    }

    func testUnderscoreNotPaired() {
        // Same reason as `*`.
        XCTAssertNil(MarkdownAutoPair.closer(for: "_"))
    }

    func testMultiCharInputNotPaired() {
        // IME composition runs deliver multi-char inserts; let those
        // through to the standard insertText path.
        XCTAssertNil(MarkdownAutoPair.closer(for: "abc"))
    }

    func testEmptyStringNotPaired() {
        XCTAssertNil(MarkdownAutoPair.closer(for: ""))
    }

    func testRandomCharNotPaired() {
        XCTAssertNil(MarkdownAutoPair.closer(for: "x"))
    }
}
