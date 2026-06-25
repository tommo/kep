import XCTest
@testable import KepMarkdown

final class MarkdownListContinuationTests: XCTestCase {

    func testDashBulletContinues() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "- foo"), .insert("- "))
    }

    func testStarBulletContinues() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "* foo"), .insert("* "))
    }

    func testPlusBulletContinues() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "+ foo"), .insert("+ "))
    }

    func testNumericMarkerIncrements() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "3. third"), .insert("4. "))
    }

    // MARK: - Task checkboxes (Obsidian parity)

    func testUncheckedTaskContinuesAsFreshBox() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "- [ ] buy milk"), .insert("- [ ] "))
    }

    func testCheckedTaskContinuesAsUncheckedBox() {
        // A ticked item must NOT carry its tick to the next line.
        XCTAssertEqual(MarkdownListContinuation.action(for: "- [x] done"), .insert("- [ ] "))
        XCTAssertEqual(MarkdownListContinuation.action(for: "* [X] done"), .insert("* [ ] "))
    }

    func testTaskCheckboxKeepsIndent() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "    - [ ] nested"), .insert("    - [ ] "))
    }

    func testEmptyTaskBreaksOut() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "- [ ] "), .clearMarker)
    }

    func testMalformedCheckboxFallsBackToBullet() {
        // No trailing space inside the brackets → it's just a bullet line.
        XCTAssertEqual(MarkdownListContinuation.action(for: "- [] foo"), .insert("- "))
    }

    func testNumericMarkerDoubleDigit() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "10. ten"), .insert("11. "))
    }

    func testIndentPreserved() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "  - inner"), .insert("  - "))
    }

    func testTabIndentPreserved() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "\t- inner"), .insert("\t- "))
    }

    func testEmptyMarkerBreaksOut() {
        // "- " (just the marker, no body) signals "I'm done with this list"
        XCTAssertEqual(MarkdownListContinuation.action(for: "- "), .clearMarker)
    }

    func testEmptyNumericMarkerBreaksOut() {
        XCTAssertEqual(MarkdownListContinuation.action(for: "1. "), .clearMarker)
    }

    func testNonListLineFallsThrough() {
        XCTAssertNil(MarkdownListContinuation.action(for: "plain text"))
    }

    func testEmptyLineFallsThrough() {
        XCTAssertNil(MarkdownListContinuation.action(for: ""))
    }

    func testDashWithoutSpaceIsNotMarker() {
        // "-foo" isn't a markdown bullet; needs "- " (marker + space).
        XCTAssertNil(MarkdownListContinuation.action(for: "-foo"))
    }

    func testNumericWithoutSpaceIsNotMarker() {
        XCTAssertNil(MarkdownListContinuation.action(for: "1.foo"))
    }

    // MARK: - leadingIndent (powers indent-preservation on Enter)

    func testLeadingIndentSpaces() {
        XCTAssertEqual(MarkdownListContinuation.leadingIndent(of: "    hello"), "    ")
    }

    func testLeadingIndentTabs() {
        XCTAssertEqual(MarkdownListContinuation.leadingIndent(of: "\t\thello"), "\t\t")
    }

    func testLeadingIndentMixed() {
        XCTAssertEqual(MarkdownListContinuation.leadingIndent(of: "  \t hello"), "  \t ")
    }

    func testLeadingIndentEmpty() {
        XCTAssertEqual(MarkdownListContinuation.leadingIndent(of: "hello"), "")
    }

    func testLeadingIndentBlankLineIsAllWhitespace() {
        // Whitespace-only line is "all indent" — preserving it is the
        // expected behavior (matches what code editors do for empty lines).
        XCTAssertEqual(MarkdownListContinuation.leadingIndent(of: "   "), "   ")
    }
}
