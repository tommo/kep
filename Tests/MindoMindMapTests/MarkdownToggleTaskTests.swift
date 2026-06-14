import XCTest
@testable import MindoMarkdown

/// MarkdownFormatting.toggleTask — the "toggle checkbox status" action.
final class MarkdownToggleTaskTests: XCTestCase {

    private func toggled(_ text: String, _ range: NSRange) -> String {
        MarkdownFormatting.toggleTask(text, range: range).0
    }

    func testUncheckedBecomesChecked() {
        XCTAssertEqual(toggled("- [ ] buy milk", NSRange(location: 0, length: 0)), "- [x] buy milk")
    }

    func testCheckedBecomesUnchecked() {
        XCTAssertEqual(toggled("- [x] done", NSRange(location: 0, length: 0)), "- [ ] done")
        XCTAssertEqual(toggled("- [X] done", NSRange(location: 0, length: 0)), "- [ ] done")
    }

    func testPlainBulletGainsCheckbox() {
        XCTAssertEqual(toggled("- groceries", NSRange(location: 0, length: 0)), "- [ ] groceries")
        XCTAssertEqual(toggled("* star", NSRange(location: 0, length: 0)), "* [ ] star")
    }

    func testPlainTextBecomesTask() {
        XCTAssertEqual(toggled("just text", NSRange(location: 0, length: 0)), "- [ ] just text")
    }

    func testIndentIsPreserved() {
        XCTAssertEqual(toggled("    - [ ] nested", NSRange(location: 0, length: 0)), "    - [x] nested")
        XCTAssertEqual(toggled("  deep text", NSRange(location: 0, length: 0)), "  - [ ] deep text")
    }

    func testMultiLineSelectionTogglesEachLine() {
        let text = "- [ ] a\n- [ ] b\n- [ ] c"
        // Select the whole block.
        let out = toggled(text, NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(out, "- [x] a\n- [x] b\n- [x] c", "every selected task line flips")
    }

    func testMixedBlockNormalisesToTasks() {
        let text = "- [ ] task\nplain\n- bullet"
        let out = toggled(text, NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(out, "- [x] task\n- [ ] plain\n- [ ] bullet")
    }

    func testBlankLinesUntouched() {
        let text = "- [ ] a\n\n- [ ] b"
        let out = toggled(text, NSRange(location: 0, length: (text as NSString).length))
        XCTAssertEqual(out, "- [x] a\n\n- [x] b", "the empty middle line stays empty")
    }
}
