import XCTest
import MindoBase

final class NodeJumpModelTests: XCTestCase {

    private func items() -> [OutlineItem] {
        [
            OutlineItem(title: "Root", depth: 0, target: "t0"),
            OutlineItem(title: "Alpha", depth: 1, target: "t1"),
            OutlineItem(title: "Beta", depth: 1, target: "t2"),
            OutlineItem(title: "Alphabet soup", depth: 2, target: "t3"),
        ]
    }

    func testEmptyQueryShowsAllNodes() {
        let m = NodeJumpModel(items: items())
        XCTAssertEqual(m.results.count, 4, "empty query lists every node")
        XCTAssertEqual(m.selectedItem?.target, "t0", "selection starts at the top")
    }

    func testQueryFiltersByTitle() {
        let m = NodeJumpModel(items: items())
        m.setQuery("alph")
        let titles = m.results.map { $0.item.title }
        XCTAssertTrue(titles.contains("Alpha"))
        XCTAssertTrue(titles.contains("Alphabet soup"))
        XCTAssertFalse(titles.contains("Beta"), "non-matching nodes drop out")
    }

    func testSetQueryResetsSelectionToTop() {
        let m = NodeJumpModel(items: items())
        m.move(2)
        XCTAssertEqual(m.selection, 2)
        m.setQuery("a")
        XCTAssertEqual(m.selection, 0, "retyping puts the best match under the cursor")
    }

    func testMoveClampsWithoutWrapping() {
        let m = NodeJumpModel(items: items())
        m.move(-1)
        XCTAssertEqual(m.selection, 0, "up at the top stays")
        m.move(100)
        XCTAssertEqual(m.selection, 3, "down past the end clamps to the last row")
    }

    func testSelectedItemTracksSelection() {
        let m = NodeJumpModel(items: items())
        m.move(1)
        XCTAssertEqual(m.selectedItem?.target, "t1")
    }
}
