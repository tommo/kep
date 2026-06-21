import XCTest
@testable import MindoMarkdown

final class ProseMarkdownTests: XCTestCase {
    func testHeadings() {
        XCTAssertEqual(ProseMarkdown.classify("# Title"), .heading(level: 1, text: "Title"))
        XCTAssertEqual(ProseMarkdown.classify("### Sub"), .heading(level: 3, text: "Sub"))
        // 7 hashes is not a heading; '#' with no space isn't either.
        XCTAssertEqual(ProseMarkdown.classify("#nospace"), .text("#nospace"))
        XCTAssertEqual(ProseMarkdown.classify("####### too many"), .text("####### too many"))
    }

    func testBullets() {
        XCTAssertEqual(ProseMarkdown.classify("- one"), .bullet(text: "one"))
        XCTAssertEqual(ProseMarkdown.classify("* two"), .bullet(text: "two"))
        XCTAssertEqual(ProseMarkdown.classify("+ three"), .bullet(text: "three"))
        XCTAssertEqual(ProseMarkdown.classify("-nodash"), .text("-nodash"))
    }

    func testTextAndBlank() {
        XCTAssertEqual(ProseMarkdown.classify("just prose"), .text("just prose"))
        XCTAssertEqual(ProseMarkdown.classify("   "), .blank)
        XCTAssertEqual(ProseMarkdown.classify(""), .blank)
    }

    func testLinesSplit() {
        let ls = ProseMarkdown.lines("# H\n\n- a\nbody")
        XCTAssertEqual(ls, [.heading(level: 1, text: "H"), .blank, .bullet(text: "a"), .text("body")])
    }
}
