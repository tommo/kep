import XCTest
import AppKit
@testable import MindoCSV

final class CSVFontTests: XCTestCase {

    func testClampSizeBounds() {
        XCTAssertEqual(CSVFont.clampSize(12), 12)
        XCTAssertEqual(CSVFont.clampSize(4), 9)    // floor
        XCTAssertEqual(CSVFont.clampSize(40), 16)  // ceiling
        XCTAssertEqual(CSVFont.clampSize(9), 9)
        XCTAssertEqual(CSVFont.clampSize(16), 16)
    }

    func testCellFontResolves() {
        let f = CSVFont.cell()
        XCTAssertGreaterThanOrEqual(f.pointSize, 9)
        XCTAssertLessThanOrEqual(f.pointSize, 16)
    }
}
