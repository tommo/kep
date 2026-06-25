import XCTest
@testable import KepMarkdown

final class MarkdownFormatBridgeTests: XCTestCase {

    func testCommandSelectorsAreToolbarActions() {
        // Every bridge command must name a `toolbar…` Coordinator selector.
        for c in MarkdownFormatBridge.Command.allCases {
            XCTAssertTrue(c.rawValue.hasPrefix("toolbar"), "\(c) → \(c.rawValue)")
        }
        XCTAssertEqual(MarkdownFormatBridge.Command.allCases.count, 8)
    }

    func testImageSnippetUsesRelativePathWhenDocKnown() {
        let doc = URL(fileURLWithPath: "/ws/note.md")
        let img = URL(fileURLWithPath: "/ws/assets/pic.png")
        let s = MarkdownDropFormatter.snippet(for: [img], relativeToFileAt: doc)
        XCTAssertEqual(s, "![pic](assets/pic.png)")
        // No doc → absolute path (unchanged drop behavior).
        XCTAssertEqual(MarkdownDropFormatter.snippet(for: [img]), "![pic](/ws/assets/pic.png)")
    }

    func testSanitizedTableSizeClampsAndDefaults() {
        XCTAssertEqual(MarkdownFormatBridge.sanitizedTableSize(rows: "4", cols: "5").rows, 4)
        XCTAssertEqual(MarkdownFormatBridge.sanitizedTableSize(rows: "4", cols: "5").cols, 5)
        // Defaults on garbage, clamp to 1…20.
        XCTAssertEqual(MarkdownFormatBridge.sanitizedTableSize(rows: "x", cols: "").rows, 2)
        XCTAssertEqual(MarkdownFormatBridge.sanitizedTableSize(rows: "x", cols: "").cols, 3)
        XCTAssertEqual(MarkdownFormatBridge.sanitizedTableSize(rows: "0", cols: "999").rows, 1)
        XCTAssertEqual(MarkdownFormatBridge.sanitizedTableSize(rows: "0", cols: "999").cols, 20)
    }

    func testHeadingShortcutsMatchHeadingCommands() {
        // The ⌥⌘1/2/3 map must target the same selectors as the heading commands.
        XCTAssertEqual(MarkdownDropTextView.headingShortcuts["1"],
                       Selector((MarkdownFormatBridge.Command.heading1.rawValue)))
        XCTAssertEqual(MarkdownDropTextView.headingShortcuts["2"],
                       Selector((MarkdownFormatBridge.Command.heading2.rawValue)))
        XCTAssertEqual(MarkdownDropTextView.headingShortcuts["3"],
                       Selector((MarkdownFormatBridge.Command.heading3.rawValue)))
    }

    func testUnderlyingFormattingProducesExpectedOutput() {
        // Guards that the actions target the right MarkdownFormatting funcs.
        let (h1, _) = MarkdownFormatting.heading("Title", range: NSRange(location: 0, length: 5), level: 1)
        XCTAssertTrue(h1.hasPrefix("# "))
        let (h3, _) = MarkdownFormatting.heading("Title", range: NSRange(location: 0, length: 5), level: 3)
        XCTAssertTrue(h3.hasPrefix("### "))
        let (hr, _) = MarkdownFormatting.horizontalRule("a\nb", range: NSRange(location: 1, length: 0))
        XCTAssertTrue(hr.contains("---"))
    }
}
