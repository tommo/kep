import XCTest
@testable import KepCSV

final class CSVPasteFindReplaceTests: XCTestCase {

    // MARK: - CSVPaste.plan

    func testPasteWithinBounds() {
        let block = CSVBlock(cells: [["x", "y"], ["z", "w"]])
        let plan = CSVPaste.plan(block: block, anchorRow: 1, anchorColumn: 1,
                                 currentRowCount: 4, currentColumnCount: 4)
        XCTAssertEqual(plan.requiredRowCount, 4)
        XCTAssertEqual(plan.requiredColumnCount, 4)
        XCTAssertEqual(plan.writes, [
            CSVCellWrite(row: 1, column: 1, value: "x"),
            CSVCellWrite(row: 1, column: 2, value: "y"),
            CSVCellWrite(row: 2, column: 1, value: "z"),
            CSVCellWrite(row: 2, column: 2, value: "w"),
        ])
    }

    func testPasteGrowsGridWhenOverflowing() {
        let block = CSVBlock(cells: [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]])
        let plan = CSVPaste.plan(block: block, anchorRow: 2, anchorColumn: 2,
                                 currentRowCount: 3, currentColumnCount: 3)
        XCTAssertEqual(plan.requiredRowCount, 5)
        XCTAssertEqual(plan.requiredColumnCount, 5)
        XCTAssertEqual(plan.writes.first, CSVCellWrite(row: 2, column: 2, value: "1"))
        XCTAssertEqual(plan.writes.last, CSVCellWrite(row: 4, column: 4, value: "9"))
    }

    func testPasteAtOrigin() {
        let block = CSVBlock(cells: [["h"]])
        let plan = CSVPaste.plan(block: block, anchorRow: 0, anchorColumn: 0,
                                 currentRowCount: 2, currentColumnCount: 2)
        XCTAssertEqual(plan.writes, [CSVCellWrite(row: 0, column: 0, value: "h")])
    }

    func testApplyPasteGrowsDocumentAndWrites() {
        let doc = CSVDocument(rows: [["a", "b"], ["c", "d"]], hasHeader: false)
        let block = CSVBlock(cells: [["1", "2"], ["3", "4"]])
        let plan = CSVPaste.plan(block: block, anchorRow: 1, anchorColumn: 1,
                                 currentRowCount: doc.rows.count, currentColumnCount: doc.columnCount)
        let grew = doc.applyPaste(plan)
        XCTAssertTrue(grew)
        XCTAssertEqual(doc.rows, [["a", "b", ""], ["c", "1", "2"], ["", "3", "4"]])
    }

    // MARK: - CSVMatcher

    private let grid = [["foo", "bar"], ["baz", "FOO"], ["qux", "foobar"]]

    func testMatchesRowMajorOrder() {
        let m = CSVMatcher.matches(in: grid, keyword: "foo", caseSensitive: true)
        XCTAssertEqual(m, [CSVMatch(row: 0, column: 0), CSVMatch(row: 2, column: 1)])
    }

    func testMatchesCaseInsensitiveAddsUppercaseHit() {
        let m = CSVMatcher.matches(in: grid, keyword: "foo", caseSensitive: false)
        XCTAssertEqual(m, [CSVMatch(row: 0, column: 0), CSVMatch(row: 1, column: 1), CSVMatch(row: 2, column: 1)])
    }

    func testMatchesEmptyKeywordIsEmpty() {
        XCTAssertTrue(CSVMatcher.matches(in: grid, keyword: "", caseSensitive: true).isEmpty)
    }

    func testContainsGuard() {
        XCTAssertTrue(CSVMatcher.contains(grid, keyword: "bar", caseSensitive: true))
        XCTAssertFalse(CSVMatcher.contains(grid, keyword: "zzz", caseSensitive: true))
    }

    // MARK: - CSVFindNavigator

    private let matches = [CSVMatch(row: 0, column: 1), CSVMatch(row: 1, column: 0), CSVMatch(row: 2, column: 2)]

    func testNextForwardFromNilIsFirst() {
        XCTAssertEqual(CSVFindNavigator.next(matches: matches, after: nil, direction: .forward), matches[0])
    }

    func testNextForwardWrapsAtEnd() {
        XCTAssertEqual(CSVFindNavigator.next(matches: matches, after: matches[2], direction: .forward), matches[0])
    }

    func testNextBackwardWrapsAtStart() {
        XCTAssertEqual(CSVFindNavigator.next(matches: matches, after: matches[0], direction: .backward), matches[2])
    }

    func testNextSkipsCurrentMatch() {
        XCTAssertEqual(CSVFindNavigator.next(matches: matches, after: matches[0], direction: .forward), matches[1])
    }

    func testNextEmptyMatchesIsNil() {
        XCTAssertNil(CSVFindNavigator.next(matches: [], after: nil, direction: .forward))
    }

    // MARK: - CSVReplace

    func testReplaceInCellReplacesAllOccurrences() {
        XCTAssertEqual(CSVReplace.replaceInCell("a-a-a", keyword: "a", with: "X", caseSensitive: true), "X-X-X")
    }

    func testReplaceInCellEmptyReplacementDeletes() {
        XCTAssertEqual(CSVReplace.replaceInCell("foobar", keyword: "o", with: "", caseSensitive: true), "fbar")
    }

    func testReplaceInCellCaseInsensitive() {
        XCTAssertEqual(CSVReplace.replaceInCell("FooFOO", keyword: "foo", with: "x", caseSensitive: false), "xx")
    }

    func testPlanReplaceAllOnlyChangedCells() {
        let rows = [["cat", "dog"], ["category", "fish"]]
        let writes = CSVReplace.planReplaceAll(in: rows, keyword: "cat", with: "X", caseSensitive: true)
        XCTAssertEqual(writes, [
            CSVCellWrite(row: 0, column: 0, value: "X"),
            CSVCellWrite(row: 1, column: 0, value: "Xegory"),
        ])
    }

    func testPlanReplaceAllSafeWithCommaQuoteValues() {
        // Per-cell replace never touches CSV grammar — a value with a comma
        // and quote is replaced safely (the javamind corruption fix).
        let rows = [["a,\"b\"foo"]]
        let writes = CSVReplace.planReplaceAll(in: rows, keyword: "foo", with: "Z", caseSensitive: true)
        XCTAssertEqual(writes, [CSVCellWrite(row: 0, column: 0, value: "a,\"b\"Z")])
    }

    func testApplyReplacementsReturnsCount() {
        let doc = CSVDocument(rows: [["cat", "dog"]], hasHeader: false)
        let writes = CSVReplace.planReplaceAll(in: doc.rows, keyword: "cat", with: "X", caseSensitive: true)
        XCTAssertEqual(doc.applyReplacements(writes), 1)
        XCTAssertEqual(doc.rows, [["X", "dog"]])
    }

    func testApplyReplacementsCountsOnlyInBoundsWrites() {
        // Bug (bug-hunt): setCell silently ignores an out-of-bounds row, but
        // applyReplacements returned writes.count, over-reporting.
        let doc = CSVDocument(rows: [["cat", "dog"]], hasHeader: false)
        let writes = [
            CSVCellWrite(row: 0, column: 0, value: "X"),
            CSVCellWrite(row: 10, column: 0, value: "Y"),   // out of bounds
        ]
        XCTAssertEqual(doc.applyReplacements(writes), 1, "only the in-bounds write counts")
        XCTAssertEqual(doc.rows, [["X", "dog"]])
    }
}
