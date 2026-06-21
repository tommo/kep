import XCTest
@testable import MindoMarkdown

final class MarkdownFormatBridgeTests: XCTestCase {

    func testCommandSelectorsAreToolbarActions() {
        // Every bridge command must name a `toolbar…` Coordinator selector.
        for c in MarkdownFormatBridge.Command.allCases {
            XCTAssertTrue(c.rawValue.hasPrefix("toolbar"), "\(c) → \(c.rawValue)")
        }
        XCTAssertEqual(MarkdownFormatBridge.Command.allCases.count, 6)
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
