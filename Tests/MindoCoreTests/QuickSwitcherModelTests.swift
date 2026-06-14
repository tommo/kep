import XCTest
@testable import MindoCore

final class QuickSwitcherModelTests: XCTestCase {

    private func file(_ rel: String) -> WorkspaceFile {
        WorkspaceFile(
            url: URL(fileURLWithPath: "/ws/\(rel)"),
            workspaceName: "ws",
            relativePath: rel)
    }

    private func model(_ rels: [String], maxVisible: Int = 50) -> QuickSwitcherModel {
        QuickSwitcherModel(files: rels.map(file), maxVisible: maxVisible)
    }

    func testEmptyQueryListsAllInOrder() {
        let m = model(["a.md", "b.md", "c.md"])
        XCTAssertEqual(m.results.map(\.item.relativePath), ["a.md", "b.md", "c.md"])
        XCTAssertEqual(m.selectedFile?.relativePath, "a.md")
    }

    func testQueryFiltersAndRanks() {
        let m = model(["readme.md", "config.swift", "myconfig.swift"])
        m.setQuery("config")
        let names = m.results.map(\.item.relativePath)
        XCTAssertEqual(names.first, "config.swift")   // prefix beats mid-word
        XCTAssertFalse(names.contains("readme.md"))   // non-match dropped
    }

    func testSetQueryResetsSelectionToTop() {
        let m = model(["alpha.md", "beta.md", "gamma.md"])
        m.move(2)
        XCTAssertEqual(m.selection, 2)
        m.setQuery("a")   // all still match ('a' present in each)
        XCTAssertEqual(m.selection, 0)
    }

    func testMoveClampsAtBounds() {
        let m = model(["a.md", "b.md", "c.md"])
        m.move(-1)                       // already at 0, stays
        XCTAssertEqual(m.selection, 0)
        m.move(10)                       // past the end, clamps to last
        XCTAssertEqual(m.selection, 2)
        XCTAssertEqual(m.selectedFile?.relativePath, "c.md")
    }

    func testMoveOnEmptyResultsStaysZeroAndNoSelectedFile() {
        let m = model(["a.md"])
        m.setQuery("zzzz")               // matches nothing
        m.move(1)
        XCTAssertEqual(m.selection, 0)
        XCTAssertNil(m.selectedFile)
    }

    func testSelectAtClampsToRange() {
        let m = model(["a.md", "b.md"])
        m.select(at: 99)
        XCTAssertEqual(m.selection, 1)
        m.select(at: -5)
        XCTAssertEqual(m.selection, 0)
    }

    func testMaxVisibleCapsResults() {
        let m = model((0..<100).map { "f\($0).md" }, maxVisible: 10)
        XCTAssertEqual(m.results.count, 10)
        // Navigation is bounded by the visible slice, not the full index.
        m.move(50)
        XCTAssertEqual(m.selection, 9)
    }

    func testSelectedFileTracksHighlight() {
        let m = model(["one.md", "two.md", "three.md"])
        m.move(1)
        XCTAssertEqual(m.selectedFile?.relativePath, "two.md")
    }
}
