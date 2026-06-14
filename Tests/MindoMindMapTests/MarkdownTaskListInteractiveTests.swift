import XCTest
import AppKit
@testable import MindoMarkdown

/// End-to-end check that pressing Enter (insertNewline) inside a markdown task
/// item continues the list with a FRESH unchecked checkbox — driven through the
/// real MarkdownDropTextView, not just the pure decider.
@MainActor
final class MarkdownTaskListInteractiveTests: XCTestCase {

    private func makeTextView(_ text: String, caret: Int) -> MarkdownDropTextView {
        let tv = MarkdownDropTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        tv.string = text
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        return tv
    }

    func testEnterOnCheckedTaskInsertsFreshUncheckedBox() {
        let tv = makeTextView("- [x] done", caret: 10)
        tv.insertNewline(nil)
        XCTAssertEqual(tv.string, "- [x] done\n- [ ] ",
                       "Enter continues a task list with a new unchecked box, dropping the tick")
    }

    func testEnterOnUncheckedTaskContinuesBox() {
        let tv = makeTextView("- [ ] buy milk", caret: 14)
        tv.insertNewline(nil)
        XCTAssertEqual(tv.string, "- [ ] buy milk\n- [ ] ")
    }

    func testEnterOnEmptyTaskBreaksOut() {
        let tv = makeTextView("- [ ] ", caret: 6)
        tv.insertNewline(nil)
        XCTAssertEqual(tv.string, "", "Enter on an empty task clears the marker, exiting the list")
    }

    func testNestedTaskKeepsIndent() {
        let tv = makeTextView("    - [ ] nested", caret: 16)
        tv.insertNewline(nil)
        XCTAssertEqual(tv.string, "    - [ ] nested\n    - [ ] ")
    }
}
