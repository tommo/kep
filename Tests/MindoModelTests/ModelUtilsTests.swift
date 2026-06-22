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
        // Internal backtick runs only widen the fence (no padding needed).
        XCTAssertEqual(ModelUtils.makeMDCodeBlock("has `one` mid"), "``has `one` mid``")
        // A value ENDING in a backtick is space-padded (#211) so the edge tick
        // can't merge with the closing fence; fence width still tracks the run.
        XCTAssertEqual(ModelUtils.makeMDCodeBlock("has `one`"), "`` has `one` ``")
        XCTAssertEqual(ModelUtils.makeMDCodeBlock("has ``two``"), "``` has ``two`` ```")
    }

    func testAttributeValueEscapeRoundTrips() {
        // NOTE: a value with BOTH leading and trailing spaces can't round-trip
        // (CommonMark strips one space each side) — a known substrate limit; the
        // typed-property text layer trims, so it never emits one.
        for v in ["plain", "ends in tick`", "`", "a\nb", #"back\slash"#, "café 日本語"] {
            let encoded = ModelUtils.makeMDCodeBlock(v)
            // Peel the fence the same way the parser does, then reverse the codec.
            let run = ModelUtils.calcMaxBacktickRun(in: encoded)
            // The outer fence is the longest leading run of backticks.
            var lead = 0
            for ch in encoded { if ch == "`" { lead += 1 } else { break } }
            XCTAssertGreaterThan(lead, 0)
            XCTAssertLessThanOrEqual(lead, run)
            let inner = String(encoded.dropFirst(lead).dropLast(lead))
            let decoded = ModelUtils.unescapeAttributeValue(ModelUtils.stripCodeSpanPadding(inner))
            XCTAssertEqual(decoded, v, "value \(String(reflecting: v)) must survive the attribute codec")
        }
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
