import XCTest
import CoreGraphics
@testable import MindoCSV

/// Pure grid geometry + selection model for the spreadsheet CSVGridView (P1).
final class CSVGridGeometryTests: XCTestCase {

    private func geo(cols: Int = 3, rows: Int = 4) -> CSVGridGeometry {
        CSVGridGeometry(rowHeight: 20, headerHeight: 20, gutterWidth: 40,
                        columnWidths: Array(repeating: 100, count: cols), rowCount: rows)
    }

    func testContentSize() {
        let g = geo(cols: 3, rows: 4)
        XCTAssertEqual(g.contentSize, CGSize(width: 40 + 300, height: 20 + 80))
    }

    func testCellRect() {
        let g = geo()
        XCTAssertEqual(g.cellRect(row: 0, col: 0), CGRect(x: 40, y: 20, width: 100, height: 20))
        XCTAssertEqual(g.cellRect(row: 2, col: 1), CGRect(x: 140, y: 60, width: 100, height: 20))
        XCTAssertEqual(g.cellRect(row: 0, col: 9), .zero, "out-of-range column → zero rect")
    }

    func testHeaderGutterCorner() {
        let g = geo()
        XCTAssertEqual(g.cornerRect, CGRect(x: 0, y: 0, width: 40, height: 20))
        XCTAssertEqual(g.columnHeaderRect(1), CGRect(x: 140, y: 0, width: 100, height: 20))
        XCTAssertEqual(g.rowGutterRect(2), CGRect(x: 0, y: 60, width: 40, height: 20))
    }

    func testVariableColumnWidths() {
        let g = CSVGridGeometry(rowHeight: 20, headerHeight: 20, gutterWidth: 40,
                                columnWidths: [60, 120, 80], rowCount: 2)
        XCTAssertEqual(g.columnX(0), 40)
        XCTAssertEqual(g.columnX(1), 100)
        XCTAssertEqual(g.columnX(2), 220)
        XCTAssertEqual(g.cellRect(row: 0, col: 1), CGRect(x: 100, y: 20, width: 120, height: 20))
    }

    func testPointToCell() {
        let g = geo() // gutter 40, header 20, cols 100 wide, rows 20 tall
        XCTAssertEqual(g.cell(at: CGPoint(x: 50, y: 30)), CSVCellRef(row: 0, col: 0))
        XCTAssertEqual(g.cell(at: CGPoint(x: 145, y: 65)), CSVCellRef(row: 2, col: 1))
        XCTAssertNil(g.cell(at: CGPoint(x: 20, y: 30)), "in the gutter → no cell")
        XCTAssertNil(g.cell(at: CGPoint(x: 50, y: 10)), "in the header → no cell")
        XCTAssertNil(g.cell(at: CGPoint(x: 5000, y: 30)), "past last column → nil")
        XCTAssertNil(g.cell(at: CGPoint(x: 50, y: 5000)), "past last row → nil")
    }

    func testRangeRect() {
        let g = geo()
        // A1:B2 → covers cells (0,0)..(1,1)
        XCTAssertEqual(g.rangeRect(top: 0, left: 0, bottom: 1, right: 1),
                       CGRect(x: 40, y: 20, width: 200, height: 40))
    }

    // MARK: - Selection model

    func testSelectionSingleThenExtend() {
        var sel = CSVSelectionModel(CSVCellRef(row: 1, col: 1))
        XCTAssertTrue(sel.isSingle)
        sel.extend(to: CSVCellRef(row: 3, col: 2))
        XCTAssertFalse(sel.isSingle)
        XCTAssertEqual([sel.top, sel.left, sel.bottom, sel.right], [1, 1, 3, 2])
        XCTAssertTrue(sel.contains(CSVCellRef(row: 2, col: 2)))
        XCTAssertFalse(sel.contains(CSVCellRef(row: 0, col: 0)))
        XCTAssertEqual(sel.cells.count, 3 * 2)
    }

    func testExtendKeepsAnchorMoveCollapses() {
        var sel = CSVSelectionModel(CSVCellRef(row: 2, col: 2))
        sel.extend(to: CSVCellRef(row: 0, col: 0))    // drag up-left
        XCTAssertEqual(sel.anchor, CSVCellRef(row: 2, col: 2))
        XCTAssertEqual([sel.top, sel.left], [0, 0])   // bbox normalizes
        sel.moveActive(to: CSVCellRef(row: 5, col: 1))
        XCTAssertTrue(sel.isSingle)
        XCTAssertEqual(sel.anchor, sel.active)
    }

    func testClamp() {
        var sel = CSVSelectionModel(CSVCellRef(row: 9, col: 9))
        sel.extend(to: CSVCellRef(row: 0, col: 0))
        sel.clamp(rows: 3, cols: 2)
        XCTAssertEqual(sel.anchor, CSVCellRef(row: 2, col: 1))
        XCTAssertEqual(sel.active, CSVCellRef(row: 0, col: 0))
    }
}
