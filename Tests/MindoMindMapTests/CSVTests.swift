import XCTest
import MindoCSV

final class CSVDocumentTests: XCTestCase {

    func testParsesSimpleCSV() {
        let doc = CSVDocument.parse("a,b,c\n1,2,3\n4,5,6\n")
        XCTAssertEqual(doc.rows.count, 3)
        XCTAssertEqual(doc.rows[0], ["a", "b", "c"])
        XCTAssertEqual(doc.rows[1], ["1", "2", "3"])
        XCTAssertEqual(doc.headers, ["a", "b", "c"])
        XCTAssertEqual(doc.bodyRows.count, 2)
    }

    func testParsesQuotedFieldsWithCommasAndNewlines() {
        let doc = CSVDocument.parse("name,quote\nAda,\"Hello, world\"\nBob,\"line1\nline2\"\n")
        XCTAssertEqual(doc.rows.count, 3)
        XCTAssertEqual(doc.rows[1], ["Ada", "Hello, world"])
        XCTAssertEqual(doc.rows[2], ["Bob", "line1\nline2"])
    }

    func testEscapedDoubleQuotes() {
        let doc = CSVDocument.parse("a,b\n\"he said \"\"hi\"\"\",ok\n")
        XCTAssertEqual(doc.rows[1], [#"he said "hi""#, "ok"])
    }

    func testCRLFLineEndings() {
        let doc = CSVDocument.parse("a,b\r\n1,2\r\n3,4\r\n")
        XCTAssertEqual(doc.rows.count, 3)
        XCTAssertEqual(doc.rows[2], ["3", "4"])
    }

    func testRoundTripPreservesValues() {
        let original = "name,note\nAda,\"Hello, world\"\nBob,\"with \"\"quotes\"\"\"\n"
        let doc = CSVDocument.parse(original)
        let serialized = doc.serialize()
        let reparsed = CSVDocument.parse(serialized)
        XCTAssertEqual(reparsed.rows, doc.rows)
    }

    func testNormalizePadsShortRows() {
        let doc = CSVDocument(rows: [["a", "b", "c"], ["1"]])
        doc.normalize()
        XCTAssertEqual(doc.rows[1], ["1", "", ""])
    }

    func testColumnAndRowMutations() {
        let doc = CSVDocument(rows: [["a", "b"], ["1", "2"]])
        doc.appendRow()
        XCTAssertEqual(doc.rows.count, 3)
        XCTAssertEqual(doc.rows[2], ["", ""])
        doc.appendColumn()
        XCTAssertEqual(doc.columnCount, 3)
        XCTAssertEqual(doc.rows[0].count, 3)
        doc.setCell(row: 0, column: 2, to: "c")
        XCTAssertEqual(doc.rows[0][2], "c")
        doc.removeColumn(at: 0)
        XCTAssertEqual(doc.rows[0], ["b", "c"])
        doc.removeRow(at: 0)
        XCTAssertEqual(doc.rows.count, 2)
    }

    func testEmptyInputProducesSingleEmptyCell() {
        let doc = CSVDocument.parse("")
        XCTAssertEqual(doc.rows, [[""]])
    }

    func testTrailingBlankLineIsDropped() {
        let doc = CSVDocument.parse("a,b\n1,2\n\n\n")
        XCTAssertEqual(doc.rows.count, 2)
    }

    // MARK: - Sort

    func testSortByColumnAscendingPreservesHeader() {
        let doc = CSVDocument.parse("name,age\nCharlie,30\nAlice,40\nBob,20\n")
        doc.sort(byColumn: 0, ascending: true)
        XCTAssertEqual(doc.rows[0], ["name", "age"], "header row stays put")
        XCTAssertEqual(doc.rows[1], ["Alice", "40"])
        XCTAssertEqual(doc.rows[2], ["Bob", "20"])
        XCTAssertEqual(doc.rows[3], ["Charlie", "30"])
    }

    func testSortByColumnDescending() {
        let doc = CSVDocument.parse("k\nb\na\nc\n")
        doc.sort(byColumn: 0, ascending: false)
        XCTAssertEqual(doc.bodyRows.map { $0[0] }, ["c", "b", "a"])
    }

    func testSortNumericComparisonWhenBothCellsParse() {
        // Substring sort would put "10" before "2"; numeric compare puts 2 first.
        let doc = CSVDocument.parse("n\n10\n2\n100\n3\n")
        doc.sort(byColumn: 0, ascending: true)
        XCTAssertEqual(doc.bodyRows.map { $0[0] }, ["2", "3", "10", "100"])
    }

    func testSortFallsBackToCaseInsensitiveStringCompare() {
        let doc = CSVDocument(rows: [["x"], ["banana"], ["Apple"], ["cherry"]], hasHeader: true)
        doc.sort(byColumn: 0, ascending: true)
        // Case-insensitive: Apple, banana, cherry.
        XCTAssertEqual(doc.bodyRows.map { $0[0] }, ["Apple", "banana", "cherry"])
    }

    func testSortIgnoresOutOfBoundsColumn() {
        let doc = CSVDocument.parse("a\n1\n2\n")
        doc.sort(byColumn: 99, ascending: true)
        XCTAssertEqual(doc.rows.count, 3, "out-of-range column is a no-op, doesn't crash")
    }

    // MARK: - Multi-row delete (descending iteration keeps indices stable)

    func testDescendingRemovalOfMultipleRowsLeavesCorrectSurvivors() {
        let doc = CSVDocument.parse("h\nA\nB\nC\nD\nE\n")
        // Editor removes selected indices (0-based against bodyRows: A=0..E=4)
        // by walking in descending order, mapping each to rows index by adding
        // 1 for the header offset.
        let bodySelections = IndexSet([0, 2, 4]) // A, C, E
        for i in bodySelections.reversed() {
            doc.removeRow(at: doc.hasHeader ? i + 1 : i)
        }
        XCTAssertEqual(doc.bodyRows.map { $0[0] }, ["B", "D"])
    }

    func testDescendingRemovalOfMultipleColumnsLeavesCorrectSurvivors() {
        let doc = CSVDocument.parse("a,b,c,d,e\n1,2,3,4,5\n")
        for i in IndexSet([1, 3]).reversed() { // remove b, d
            doc.removeColumn(at: i)
        }
        XCTAssertEqual(doc.rows[0], ["a", "c", "e"])
        XCTAssertEqual(doc.rows[1], ["1", "3", "5"])
    }

    func testSnapshotRestoreRoundTripsTheRowsArray() {
        // Mirrors the editor's undo path: take a snapshot, mutate, restore.
        let doc = CSVDocument.parse("h\nA\nB\nC\n")
        let snapshot = doc.rows
        doc.appendRow()
        doc.setCell(row: 1, column: 0, to: "MUTATED")
        XCTAssertNotEqual(doc.rows, snapshot)
        doc.rows = snapshot
        XCTAssertEqual(doc.rows, snapshot)
    }

    // MARK: - Insert at index

    func testInsertRowAtMiddle() {
        let doc = CSVDocument(rows: [["A"], ["B"], ["C"]], hasHeader: false)
        doc.insertRow(at: 1)
        XCTAssertEqual(doc.rows.map { $0.first ?? "" }, ["A", "", "B", "C"])
    }

    func testInsertRowAtZeroPrependsBeforeAllRows() {
        let doc = CSVDocument(rows: [["A"], ["B"]], hasHeader: false)
        doc.insertRow(at: 0)
        XCTAssertEqual(doc.rows.map { $0.first ?? "" }, ["", "A", "B"])
    }

    func testInsertRowPastEndAppends() {
        let doc = CSVDocument(rows: [["A"]], hasHeader: false)
        doc.insertRow(at: 999)
        XCTAssertEqual(doc.rows.count, 2)
        XCTAssertEqual(doc.rows.last?.first, "")
    }

    func testInsertRowAtNegativeClampsToZero() {
        let doc = CSVDocument(rows: [["A"]], hasHeader: false)
        doc.insertRow(at: -5)
        XCTAssertEqual(doc.rows.map { $0.first ?? "" }, ["", "A"])
    }

    func testInsertRowMatchesColumnCount() {
        // New row must have one cell per column so the table view sees
        // a clean rectangle without normalize().
        let doc = CSVDocument(rows: [["a", "b", "c"]], hasHeader: false)
        doc.insertRow(at: 1)
        XCTAssertEqual(doc.rows[1].count, 3)
        XCTAssertTrue(doc.rows[1].allSatisfy { $0.isEmpty })
    }

    func testInsertColumnAtMiddle() {
        let doc = CSVDocument(rows: [["A", "B", "C"], ["1", "2", "3"]], hasHeader: false)
        doc.insertColumn(at: 1)
        XCTAssertEqual(doc.rows[0], ["A", "", "B", "C"])
        XCTAssertEqual(doc.rows[1], ["1", "", "2", "3"])
    }

    func testInsertColumnPastEndAppends() {
        let doc = CSVDocument(rows: [["A", "B"]], hasHeader: false)
        doc.insertColumn(at: 999)
        XCTAssertEqual(doc.rows[0], ["A", "B", ""])
    }

    func testInsertColumnPadsShortRowsFirst() {
        // Rows of uneven length must end up rectangular after insert,
        // matching the documented invariant in CSVDocument.normalize.
        let doc = CSVDocument(rows: [["A", "B"], ["X"]], hasHeader: false)
        doc.insertColumn(at: 1)
        XCTAssertEqual(doc.rows[0].count, 3)
        XCTAssertEqual(doc.rows[1].count, 3)
        XCTAssertEqual(doc.rows[1], ["X", "", ""])
    }

    // MARK: - Clear cells

    func testClearCellEmptiesAndReportsChange() {
        let doc = CSVDocument(rows: [["A", "B"], ["C", "D"]], hasHeader: false)
        XCTAssertTrue(doc.clearCell(row: 0, column: 1))
        XCTAssertEqual(doc.rows[0], ["A", ""])
    }

    func testClearAlreadyEmptyCellReturnsFalse() {
        // Critical for the Delete handler — caller skips the undo
        // registration when nothing actually changed.
        let doc = CSVDocument(rows: [["", "B"]], hasHeader: false)
        XCTAssertFalse(doc.clearCell(row: 0, column: 0))
    }

    func testClearOutOfRangeCellReturnsFalse() {
        let doc = CSVDocument(rows: [["A"]], hasHeader: false)
        XCTAssertFalse(doc.clearCell(row: 0, column: 99))
        XCTAssertFalse(doc.clearCell(row: -1, column: 0))
        XCTAssertFalse(doc.clearCell(row: 99, column: 0))
        XCTAssertEqual(doc.rows, [["A"]])
    }

    func testClearCellsBatchReturnsChangeCount() {
        let doc = CSVDocument(rows: [["A", "B", "C"], ["D", "", "F"]], hasHeader: false)
        let n = doc.clearCells([
            (row: 0, column: 0), (row: 0, column: 1),
            (row: 1, column: 1), (row: 1, column: 2),
        ])
        // (1,1) was already empty — only 3 actual changes.
        XCTAssertEqual(n, 3)
        XCTAssertEqual(doc.rows[0], ["", "", "C"])
        XCTAssertEqual(doc.rows[1], ["D", "", ""])
    }
}

import AppKit
@testable import MindoCSV

/// Guards the rank-2 fix: NSTableView silently ignores column selection
/// unless `allowsColumnSelection` is set, which is what left every CSV
/// column op (Delete Column / Delete-clear / insert-at-selection) a dead
/// no-op. These assert the flag actually governs selectability.
final class CSVColumnSelectionTests: XCTestCase {

    private func makeTable(columns: Int) -> CSVTableView {
        let table = CSVTableView()
        for i in 0..<columns {
            table.addTableColumn(NSTableColumn(identifier: .init("col\(i)")))
        }
        return table
    }

    func testColumnSelectionIgnoredWhenFlagOff() {
        let table = makeTable(columns: 3)
        table.allowsColumnSelection = false
        table.selectColumnIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        // Defends against accidentally reverting the fix: with the flag off
        // the selection never takes, so the column ops have nothing to act on.
        XCTAssertTrue(table.selectedColumnIndexes.isEmpty)
    }

    func testColumnSelectionTakesWhenFlagOn() {
        let table = makeTable(columns: 3)
        table.allowsColumnSelection = true
        table.selectColumnIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertEqual(table.selectedColumnIndexes, IndexSet(integer: 1))
    }

    func testMultipleColumnSelectionWithFlagOn() {
        let table = makeTable(columns: 4)
        table.allowsColumnSelection = true
        table.allowsMultipleSelection = true
        table.selectColumnIndexes(IndexSet([0, 2]), byExtendingSelection: false)
        XCTAssertEqual(table.selectedColumnIndexes, IndexSet([0, 2]))
    }
}

/// The pure cell-selection resolver behind Delete-to-clear. NSTableView
/// row/column selection is mutually exclusive, so these assert each mode
/// maps to the right document cells (and never the header row).
final class CSVCellSelectionTests: XCTestCase {
    private func sorted(_ cells: [(row: Int, column: Int)]) -> [[Int]] {
        cells.map { [$0.row, $0.column] }.sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }
    }

    func testColumnSelectionClearsWholeColumnsAcrossBodyRows() {
        // 3 body rows, 3 cols, header present → doc rows 1..3, col 1.
        let cells = CSVCellSelection.cellsToClear(
            selectedViewRows: IndexSet(), selectedColumns: IndexSet(integer: 1),
            bodyRowCount: 3, columnCount: 3, hasHeader: true)
        XCTAssertEqual(sorted(cells), [[1, 1], [2, 1], [3, 1]])
    }

    func testRowSelectionClearsWholeRowsAcrossColumns() {
        // view row 0, header present → doc row 1, all 3 cols.
        let cells = CSVCellSelection.cellsToClear(
            selectedViewRows: IndexSet(integer: 0), selectedColumns: IndexSet(),
            bodyRowCount: 2, columnCount: 3, hasHeader: true)
        XCTAssertEqual(sorted(cells), [[1, 0], [1, 1], [1, 2]])
    }

    func testNoHeaderUsesViewRowsDirectly() {
        let cells = CSVCellSelection.cellsToClear(
            selectedViewRows: IndexSet(integer: 0), selectedColumns: IndexSet(integer: 2),
            bodyRowCount: 2, columnCount: 3, hasHeader: false)
        XCTAssertEqual(sorted(cells), [[0, 2]])
    }

    func testIntersectionWhenBothSelected() {
        // Defensive both-selected path → rectangular intersection.
        let cells = CSVCellSelection.cellsToClear(
            selectedViewRows: IndexSet([0, 1]), selectedColumns: IndexSet([0, 2]),
            bodyRowCount: 3, columnCount: 3, hasHeader: false)
        XCTAssertEqual(sorted(cells), [[0, 0], [0, 2], [1, 0], [1, 2]])
    }

    func testEmptySelectionsYieldNothing() {
        let cells = CSVCellSelection.cellsToClear(
            selectedViewRows: IndexSet(), selectedColumns: IndexSet(),
            bodyRowCount: 3, columnCount: 3, hasHeader: true)
        XCTAssertTrue(cells.isEmpty)
    }

    func testOutOfRangeIndicesAreFiltered() {
        let cells = CSVCellSelection.cellsToClear(
            selectedViewRows: IndexSet(), selectedColumns: IndexSet([1, 99]),
            bodyRowCount: 1, columnCount: 2, hasHeader: false)
        XCTAssertEqual(sorted(cells), [[0, 1]])   // col 99 dropped
    }

    func testEmptyDocumentYieldsNothing() {
        let cells = CSVCellSelection.cellsToClear(
            selectedViewRows: IndexSet(integer: 0), selectedColumns: IndexSet(),
            bodyRowCount: 0, columnCount: 0, hasHeader: true)
        XCTAssertTrue(cells.isEmpty)
    }
}
