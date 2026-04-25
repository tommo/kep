import XCTest
import MindoMarkdown

final class MarkdownFormattingTests: XCTestCase {

    private func nsRange(_ loc: Int, _ len: Int) -> NSRange { NSRange(location: loc, length: len) }

    func testBoldWrapsSelection() {
        let (text, range) = MarkdownFormatting.bold("hello world", range: nsRange(6, 5))
        XCTAssertEqual(text, "hello **world**")
        XCTAssertEqual(range, nsRange(8, 5))
    }

    func testBoldTogglesOff() {
        let (text, range) = MarkdownFormatting.bold("hello **world**", range: nsRange(8, 5))
        XCTAssertEqual(text, "hello world")
        XCTAssertEqual(range, nsRange(6, 5))
    }

    func testItalicWrapsWithSingleStar() {
        let (text, _) = MarkdownFormatting.italic("hi", range: nsRange(0, 2))
        XCTAssertEqual(text, "*hi*")
    }

    func testInlineCodeUsesBackticks() {
        let (text, _) = MarkdownFormatting.inlineCode("foo", range: nsRange(0, 3))
        XCTAssertEqual(text, "`foo`")
    }

    func testEmptySelectionInsertsPlaceholder() {
        let (text, range) = MarkdownFormatting.bold("", range: nsRange(0, 0))
        XCTAssertEqual(text, "**text**")
        XCTAssertEqual(range, nsRange(2, 4))
    }

    func testHeadingPrependsHashes() {
        let (text, _) = MarkdownFormatting.heading("hello", range: nsRange(0, 0), level: 2)
        XCTAssertEqual(text, "## hello")
    }

    func testHeadingTogglesDepth() {
        let (text, _) = MarkdownFormatting.heading("# hello", range: nsRange(0, 0), level: 3)
        XCTAssertEqual(text, "### hello")
    }

    func testBulletListPrefixesEachLine() {
        let (text, _) = MarkdownFormatting.bulletList("a\nb\nc", range: nsRange(0, 5))
        XCTAssertEqual(text, "- a\n- b\n- c")
    }

    func testNumberedListNumbersEachLine() {
        let (text, _) = MarkdownFormatting.numberedList("a\nb\nc", range: nsRange(0, 5))
        XCTAssertEqual(text, "1. a\n2. b\n3. c")
    }

    func testBlockquotePrefixesGreaterThan() {
        let (text, _) = MarkdownFormatting.blockquote("a\nb", range: nsRange(0, 3))
        XCTAssertEqual(text, "> a\n> b")
    }

    func testLinkInsertsMarkdownLink() {
        let (text, range) = MarkdownFormatting.link("Hi", range: nsRange(0, 2), url: "https://x")
        XCTAssertEqual(text, "[Hi](https://x)")
        // Selection moves into the label so the user can retype.
        XCTAssertEqual(range, nsRange(1, 2))
    }

    func testImageInsertsBangLink() {
        let (text, _) = MarkdownFormatting.image("alt", range: nsRange(0, 3), url: "https://i")
        XCTAssertEqual(text, "![alt](https://i)")
    }
}
