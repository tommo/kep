import XCTest
@testable import MindoPlantUML

final class PlantUMLCommentToggleTests: XCTestCase {

    func testCommentSingleLine() {
        XCTAssertEqual(PlantUMLCommentToggle.toggle("hello"), "' hello")
    }

    func testCommentMultipleLines() {
        XCTAssertEqual(
            PlantUMLCommentToggle.toggle("a\nb\nc"),
            "' a\n' b\n' c"
        )
    }

    func testUncommentWhenAllCommented() {
        // Round-trip — the toggle removes the prefix it added.
        XCTAssertEqual(
            PlantUMLCommentToggle.toggle("' a\n' b\n' c"),
            "a\nb\nc"
        )
    }

    func testUncommentAcceptsBareApostrophe() {
        // PlantUML accepts `'foo` (no space) as a comment too — strip it
        // anyway so a manually-typed comment can be toggled off.
        XCTAssertEqual(PlantUMLCommentToggle.toggle("'a\n'b"), "a\nb")
    }

    func testCommentSkipsBlankLines() {
        // Blank lines stay blank — a partial selection that crosses a
        // paragraph break shouldn't sprout `' ` lines in the gap.
        XCTAssertEqual(
            PlantUMLCommentToggle.toggle("a\n\nb"),
            "' a\n\n' b"
        )
    }

    func testMixedSelectionCommentsAll() {
        // If any non-blank line lacks the prefix, the whole block gets
        // commented (matches mindolph's addOrTrim behavior).
        XCTAssertEqual(
            PlantUMLCommentToggle.toggle("' a\nb"),
            "' ' a\n' b"
        )
    }

    func testRoundTripPreservesIndent() {
        // Strip only the comment marker, not the leading whitespace.
        XCTAssertEqual(
            PlantUMLCommentToggle.toggle("  ' indented"),
            "  indented"
        )
    }

    func testEmptyBlockUnchanged() {
        XCTAssertEqual(PlantUMLCommentToggle.toggle(""), "")
        XCTAssertEqual(PlantUMLCommentToggle.toggle("\n\n"), "\n\n")
    }
}
