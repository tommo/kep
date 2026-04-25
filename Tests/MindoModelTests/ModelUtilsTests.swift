import XCTest
@testable import MindoModel

final class ModelUtilsTests: XCTestCase {

    func testEscapeMarkdownHandlesSpecialChars() {
        // Each char in the ESCAPED set should be backslash-prefixed.
        let raw = "title with . and # and (parens) and *star*"
        let escaped = ModelUtils.escapeMarkdown(raw)
        XCTAssertEqual(escaped, ##"title with \. and \# and \(parens\) and \*star\*"##)
    }

    func testEscapeMarkdownConvertsNewlinesToBR() {
        XCTAssertEqual(ModelUtils.escapeMarkdown("line1\nline2"), "line1<br/>line2")
    }

    func testUnescapeMarkdownRoundTrips() {
        let cases = [
            "Plain text",
            "with . dot and # hash",
            "multi\nline\ntext",
            "(parens) and {braces}",
            "stars *here*",
        ]
        for s in cases {
            let escaped = ModelUtils.escapeMarkdown(s)
            XCTAssertEqual(ModelUtils.unescapeMarkdown(escaped), s, "round-trip failed for: \(s)")
        }
    }

    func testMakeMDCodeBlockBumpsBacktickFenceCount() {
        XCTAssertEqual(ModelUtils.makeMDCodeBlock("plain"), "`plain`")
        XCTAssertEqual(ModelUtils.makeMDCodeBlock("has `one`"), "``has `one```")
        XCTAssertEqual(ModelUtils.makeMDCodeBlock("has ``two``"), "```has ``two`````")
    }

    func testMakePreBlockEscapesAngles() {
        XCTAssertEqual(ModelUtils.makePreBlock("a < b > c & d"), "<pre>a &lt; b &gt; c &amp; d</pre>")
    }

    func testUnescapeHtmlHandlesNamedAndNumeric() {
        XCTAssertEqual(ModelUtils.unescapeHtml("a &lt; b &amp; c"), "a < b & c")
        XCTAssertEqual(ModelUtils.unescapeHtml("&#65;&#x42;C"), "ABC")
    }

    func testCalcLeadingHashes() {
        XCTAssertEqual(ModelUtils.calcLeadingHashes("###topic"), 3)
        XCTAssertEqual(ModelUtils.calcLeadingHashes("# title"), 1)
        XCTAssertEqual(ModelUtils.calcLeadingHashes("plain"), 0)
    }
}
