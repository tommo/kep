import XCTest
@testable import MindoMarkdown

final class MarkdownPasteRuleTests: XCTestCase {

    func testHttpURLPasses() {
        XCTAssertEqual(MarkdownPasteRule.urlIfMatched("https://example.com"), "https://example.com")
    }

    func testFtpURLPasses() {
        XCTAssertEqual(MarkdownPasteRule.urlIfMatched("ftp://files.example.com/x.zip"), "ftp://files.example.com/x.zip")
    }

    func testMailtoPasses() {
        XCTAssertEqual(MarkdownPasteRule.urlIfMatched("mailto:foo@bar.com"), "mailto:foo@bar.com")
    }

    func testCaseInsensitiveSchemeMatch() {
        // Trim should preserve case in the result, but matching is case-insensitive.
        XCTAssertEqual(MarkdownPasteRule.urlIfMatched("HTTPS://Example.com"), "HTTPS://Example.com")
    }

    func testTrimsSurroundingWhitespace() {
        XCTAssertEqual(MarkdownPasteRule.urlIfMatched("  https://example.com  \n"),
                       "https://example.com")
    }

    func testSchemelessURLRejected() {
        // "www.example.com" is plain text per the conservative rule.
        XCTAssertNil(MarkdownPasteRule.urlIfMatched("www.example.com"))
    }

    func testMultiLinePayloadRejected() {
        XCTAssertNil(MarkdownPasteRule.urlIfMatched("https://a.com\nhttps://b.com"))
    }

    func testURLWithEmbeddedSpaceRejected() {
        // Almost always means the user copied a sentence containing a URL,
        // not the URL alone — fall back to plain paste.
        XCTAssertNil(MarkdownPasteRule.urlIfMatched("https://a.com and stuff"))
    }

    func testEmptyStringRejected() {
        XCTAssertNil(MarkdownPasteRule.urlIfMatched(""))
        XCTAssertNil(MarkdownPasteRule.urlIfMatched("   \n  "))
    }

    func testPlainTextRejected() {
        XCTAssertNil(MarkdownPasteRule.urlIfMatched("just some plain text"))
    }

    func testReadsFromPasteboard() {
        let pb = NSPasteboard(name: NSPasteboard.Name("MarkdownPasteRuleTests-\(UUID())"))
        pb.clearContents()
        pb.setString("https://example.com", forType: .string)
        XCTAssertEqual(MarkdownPasteRule.urlFromPasteboard(pb), "https://example.com")
    }
}
