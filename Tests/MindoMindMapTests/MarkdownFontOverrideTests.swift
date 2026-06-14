import XCTest
@testable import MindoMarkdown

final class MarkdownFontOverrideTests: XCTestCase {

    func testNoOverrideIsEmpty() {
        XCTAssertEqual(MarkdownRenderer.fontOverrideCSS(sans: nil, mono: nil), "")
        XCTAssertEqual(MarkdownRenderer.fontOverrideCSS(sans: "", mono: "   "), "")
    }

    func testSansOnlyEmitsBodyRule() {
        let css = MarkdownRenderer.fontOverrideCSS(sans: "Georgia", mono: nil)
        XCTAssertTrue(css.contains("body { font-family: \"Georgia\""))
        XCTAssertFalse(css.contains("code"))
    }

    func testMonoOnlyEmitsCodeRule() {
        let css = MarkdownRenderer.fontOverrideCSS(sans: nil, mono: "Fira Code")
        XCTAssertTrue(css.contains("code, pre, pre code { font-family: \"Fira Code\""))
        XCTAssertFalse(css.contains("body {"))
    }

    func testBothEmitsTwoRules() {
        let css = MarkdownRenderer.fontOverrideCSS(sans: "Georgia", mono: "Menlo")
        XCTAssertEqual(css.split(separator: "\n").count, 2)
    }

    func testSanitizationStripsCSSBreakers() {
        // The cleaned NAME must contain none of the characters that could
        // close the CSS string / rule and inject new declarations. (The
        // surrounding rule template legitimately uses { } ; — we check the
        // name, not the whole sheet.)
        let cleaned = MarkdownRenderer.sanitizedFontName("Evil\"; } body{display:none} \"")
        let name = try! XCTUnwrap(cleaned)
        for breaker in ["\"", ";", "{", "}"] {
            XCTAssertFalse(name.contains(breaker), "name still contains \(breaker)")
        }
    }

    func testWhitespaceOnlyNameIsIgnored() {
        XCTAssertNil(MarkdownRenderer.sanitizedFontName("   \n  "))
        XCTAssertEqual(MarkdownRenderer.sanitizedFontName("  Helvetica Neue "), "Helvetica Neue")
    }
}
