import XCTest
import KepMarkdown

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

    func testHeadingSupportsH4ThroughH6() {
        XCTAssertEqual(MarkdownFormatting.heading("x", range: nsRange(0, 0), level: 4).0, "#### x")
        XCTAssertEqual(MarkdownFormatting.heading("x", range: nsRange(0, 0), level: 5).0, "##### x")
        XCTAssertEqual(MarkdownFormatting.heading("x", range: nsRange(0, 0), level: 6).0, "###### x")
    }

    func testCodeBlockWrapsSelectionInFences() {
        // Whole-document selection: already at both boundaries, no extra blanks.
        let (text, range) = MarkdownFormatting.codeBlock("let x = 1", range: nsRange(0, 9))
        XCTAssertEqual(text, "```\nlet x = 1\n```")
        // Inner content selected (after the opening "```\n").
        XCTAssertEqual(range, nsRange(4, 9))
    }

    func testCodeBlockInsertsBlankLinesMidParagraph() {
        // Selection sits between text on both sides → fences get their own lines.
        let src = "abXYde"
        let (text, _) = MarkdownFormatting.codeBlock(src, range: nsRange(2, 2)) // "XY"
        XCTAssertEqual(text, "ab\n```\nXY\n```\nde")
    }

    func testCodeBlockEmptySelectionPlacesCaretInside() {
        let (text, range) = MarkdownFormatting.codeBlock("", range: nsRange(0, 0))
        XCTAssertEqual(text, "```\n\n```")
        XCTAssertEqual(range, nsRange(4, 0))   // caret on the empty middle line
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

    func testTableAlignmentLeftEmitsLeadingColon() {
        let (text, _) = MarkdownFormatting.table("", range: nsRange(0, 0), rows: 1, cols: 2, alignment: .left)
        XCTAssertTrue(text.contains("| :--- | :--- |"), "got:\n\(text)")
    }

    func testTableAlignmentCenterEmitsBothColons() {
        let (text, _) = MarkdownFormatting.table("", range: nsRange(0, 0), rows: 1, cols: 2, alignment: .center)
        XCTAssertTrue(text.contains("| :---: | :---: |"), "got:\n\(text)")
    }

    func testTableAlignmentRightEmitsTrailingColon() {
        let (text, _) = MarkdownFormatting.table("", range: nsRange(0, 0), rows: 1, cols: 2, alignment: .right)
        XCTAssertTrue(text.contains("| ---: | ---: |"), "got:\n\(text)")
    }

    func testTableAlignmentNoneIsTheDefault() {
        let (a, _) = MarkdownFormatting.table("", range: nsRange(0, 0), rows: 1, cols: 2)
        let (b, _) = MarkdownFormatting.table("", range: nsRange(0, 0), rows: 1, cols: 2, alignment: .none)
        XCTAssertEqual(a, b)
    }

    // MARK: - horizontalRule

    func testHorizontalRuleAtStartOfDocument() {
        // Empty leading text — no leading newlines needed; only trailing
        // newline so the rule isn't glued to whatever follows.
        let (out, sel) = MarkdownFormatting.horizontalRule("", range: nsRange(0, 0))
        XCTAssertEqual(out, "---\n")
        XCTAssertEqual(sel, nsRange(4, 0))
    }

    func testHorizontalRulePadsBlankLineBeforePlainText() {
        // Cursor right after "abc" (no trailing newline) — must add the
        // double newline before so markdown parses `---` as a rule
        // rather than a setext H2 underline. Empty tail = single
        // trailing newline (no point padding the EOF).
        let body = "abc"
        let (out, sel) = MarkdownFormatting.horizontalRule(body, range: nsRange(3, 0))
        XCTAssertEqual(out, "abc\n\n---\n")
        // Caret lands after the trailing pad so the user can keep typing.
        XCTAssertEqual(sel, nsRange((out as NSString).length, 0))
    }

    func testHorizontalRuleCollapsesExistingBlankLineBefore() {
        let body = "abc\n\n"
        let (out, _) = MarkdownFormatting.horizontalRule(body, range: nsRange(5, 0))
        XCTAssertEqual(out, "abc\n\n---\n")
    }

    func testHorizontalRuleAddsBlankAfterIfTextFollows() {
        // Tail starts with "next" — needs `\n\n` between rule + text.
        let body = "next"
        let (out, _) = MarkdownFormatting.horizontalRule(body, range: nsRange(0, 0))
        XCTAssertEqual(out, "---\n\nnext")
    }

    func testHorizontalRuleReplacesSelection() {
        let body = "before [SEL] after"
        let range = nsRange(7, 5)  // "[SEL]"
        let (out, _) = MarkdownFormatting.horizontalRule(body, range: range)
        // Selection replaced by the padded rule; "[SEL]" gone.
        XCTAssertFalse(out.contains("[SEL]"))
        XCTAssertTrue(out.contains("\n\n---\n\n"))
    }
}
