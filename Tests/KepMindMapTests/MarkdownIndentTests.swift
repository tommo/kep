import XCTest
import KepBase
@testable import KepMarkdown

final class MarkdownIndentTests: XCTestCase {

    func testIndentSingleLine() {
        XCTAssertEqual(MarkdownIndent.indent("hello"), "  hello")
    }

    func testIndentMultiLine() {
        XCTAssertEqual(MarkdownIndent.indent("a\nb\nc"), "  a\n  b\n  c")
    }

    func testIndentEmptyLinesGetIndented() {
        // Blank lines in the middle still gain the indent — keeps the
        // visual block aligned. (Editors that strip blank-line indent
        // create surprising selection edges.)
        XCTAssertEqual(MarkdownIndent.indent("a\n\nb"), "  a\n  \n  b")
    }

    func testOutdentSingleLineWithSpaces() {
        XCTAssertEqual(MarkdownIndent.outdent("  hello"), "hello")
    }

    func testOutdentSingleLineWithTab() {
        XCTAssertEqual(MarkdownIndent.outdent("\thello"), "hello")
    }

    func testOutdentMultiLineMixed() {
        // Each line gets one indent level removed independently — lines
        // without indent stay as-is.
        XCTAssertEqual(MarkdownIndent.outdent("  a\n\tb\nc"), "a\nb\nc")
    }

    func testOutdentOnlyOneLevelPerCall() {
        // Two leading levels → only the first is removed; second Shift-Tab
        // press would remove the next.
        XCTAssertEqual(MarkdownIndent.outdent("    deep"), "  deep")
    }

    func testOutdentNonIndentedLineUntouched() {
        XCTAssertEqual(MarkdownIndent.outdent("hello"), "hello")
    }

    func testRoundTripIndentOutdent() {
        let original = "first\n  second\n    third"
        XCTAssertEqual(MarkdownIndent.outdent(MarkdownIndent.indent(original)), original)
    }

    // MARK: - EditorIndent (the shared underlying helper)

    func testEditorIndentMatchesMarkdownIndent() {
        // Confirm the shim parity — same behavior on a representative input.
        let original = "alpha\n  beta\n\tgamma"
        XCTAssertEqual(KepBase.EditorIndent.indent(original), MarkdownIndent.indent(original))
        XCTAssertEqual(KepBase.EditorIndent.outdent(original), MarkdownIndent.outdent(original))
        XCTAssertEqual(KepBase.EditorIndent.unit, MarkdownIndent.unit)
    }

    // MARK: - MarkdownDropTextView.formattingShortcuts (cmd-key map)

    func testFormattingShortcutsCoverFourEntries() {
        let shortcuts = MarkdownDropTextView.formattingShortcuts
        XCTAssertEqual(Set(shortcuts.keys), ["b", "i", "e", "k"])
    }

    func testFormattingShortcutSelectorsMatchToolbarActions() {
        let shortcuts = MarkdownDropTextView.formattingShortcuts
        XCTAssertEqual(shortcuts["b"]?.description, "toolbarBold")
        XCTAssertEqual(shortcuts["i"]?.description, "toolbarItalic")
        XCTAssertEqual(shortcuts["e"]?.description, "toolbarInlineCode")
        XCTAssertEqual(shortcuts["k"]?.description, "toolbarLink")
    }
}
