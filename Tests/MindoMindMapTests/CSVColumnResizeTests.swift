import XCTest
import CoreGraphics
@testable import MindoCSV

final class CSVColumnResizeTests: XCTestCase {

    private func geo() -> CSVGridGeometry {
        // gutter 44, three 100-wide columns → right edges at 144, 244, 344.
        CSVGridGeometry(gutterWidth: 44, columnWidths: [100, 100, 100], rowCount: 3)
    }

    func testSeparatorHitWithinTolerance() {
        XCTAssertEqual(geo().columnSeparatorIndex(atX: 144), 0)   // col 0 right edge
        XCTAssertEqual(geo().columnSeparatorIndex(atX: 246), 1)   // within 4 of 244
        XCTAssertEqual(geo().columnSeparatorIndex(atX: 344), 2)   // last column edge
    }

    func testNoSeparatorMidColumn() {
        XCTAssertNil(geo().columnSeparatorIndex(atX: 100))        // mid column 0
        XCTAssertNil(geo().columnSeparatorIndex(atX: 200))
        XCTAssertNil(geo().columnSeparatorIndex(atX: 44))         // gutter/col0 left edge
    }

    func testNearestSeparatorWins() {
        // Two 6-wide columns after the gutter: edges at 50 and 56.
        let g = CSVGridGeometry(gutterWidth: 44, columnWidths: [6, 6], rowCount: 1)
        XCTAssertEqual(g.columnSeparatorIndex(atX: 50, tolerance: 4), 0)
        XCTAssertEqual(g.columnSeparatorIndex(atX: 56, tolerance: 4), 1)
        XCTAssertEqual(g.columnSeparatorIndex(atX: 53, tolerance: 4), 0) // nearer to 50
    }
}
