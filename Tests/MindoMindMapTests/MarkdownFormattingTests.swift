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

    func testStrikethroughWrapsAndToggles() {
        let (wrapped, _) = MarkdownFormatting.strikethrough("done", range: nsRange(0, 4))
        XCTAssertEqual(wrapped, "~~done~~")
        let (off, _) = MarkdownFormatting.strikethrough(wrapped, range: nsRange(2, 4))
        XCTAssertEqual(off, "done")
    }

    func testCommentWrapsSelectionWithHTMLComment() {
        let (text, range) = MarkdownFormatting.comment("draft", range: nsRange(0, 5))
        XCTAssertEqual(text, "<!-- draft -->")
        // Selection lands inside the comment for immediate retyping.
        XCTAssertEqual(range, nsRange(5, 5))
    }

    func testCommentTogglesOffWhenAlreadyCommented() {
        let starting = "<!-- draft -->"
        let (text, _) = MarkdownFormatting.comment(starting, range: nsRange(5, 5))
        XCTAssertEqual(text, "draft")
    }

    func testTableInsertsHeaderSeparatorAndBody() {
        let (text, _) = MarkdownFormatting.table("", range: nsRange(0, 0), rows: 2, cols: 3)
        XCTAssertTrue(text.contains("| Header 1 | Header 2 | Header 3 |"))
        XCTAssertTrue(text.contains("| --- | --- | --- |"))
        // Two body rows + header + separator = 4 lines (newlines join them).
        let bodyLines = text.split(separator: "\n").filter { $0.hasPrefix("|") }
        XCTAssertEqual(bodyLines.count, 4)
    }

    func testTableClampsRowsAndColsToMinimumOne() {
        let (text, _) = MarkdownFormatting.table("", range: nsRange(0, 0), rows: 0, cols: 0)
        XCTAssertTrue(text.contains("| Header 1 |"))
    }
}
