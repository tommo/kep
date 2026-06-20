import XCTest
@testable import MindoCSV

/// Pure fill-series logic for ⌘D / ⌘R (P4 of the spreadsheet plan).
final class CSVFillTests: XCTestCase {

    func testNumericArithmeticSeries() {
        XCTAssertEqual(CSVFill.fill(seed: ["1", "2"], length: 3), ["3", "4", "5"])
        XCTAssertEqual(CSVFill.fill(seed: ["2", "4", "6"], length: 2), ["8", "10"])
        XCTAssertEqual(CSVFill.fill(seed: ["10", "8"], length: 2), ["6", "4"])   // descending
    }

    func testFractionalStep() {
        XCTAssertEqual(CSVFill.fill(seed: ["1.5", "2"], length: 2), ["2.5", "3"])  // step 0.5, .0 trimmed
    }

    func testSingleValueCopies() {
        XCTAssertEqual(CSVFill.fill(seed: ["5"], length: 3), ["5", "5", "5"])
        XCTAssertEqual(CSVFill.fill(seed: ["hi"], length: 2), ["hi", "hi"])
    }

    func testTextPatternRepeatsCyclically() {
        XCTAssertEqual(CSVFill.fill(seed: ["a", "b"], length: 4), ["a", "b", "a", "b"])
        XCTAssertEqual(CSVFill.fill(seed: ["x", "y", "z"], length: 4), ["x", "y", "z", "x"])
    }

    func testNonConstantStepIsPatternNotSeries() {
        // 1,2,4 isn't arithmetic → repeats the pattern rather than inventing a series.
        XCTAssertEqual(CSVFill.fill(seed: ["1", "2", "4"], length: 3), ["1", "2", "4"])
    }

    func testMixedNumericTextRepeats() {
        XCTAssertEqual(CSVFill.fill(seed: ["1", "x"], length: 4), ["1", "x", "1", "x"])
    }

    func testEdgeCases() {
        XCTAssertEqual(CSVFill.fill(seed: [], length: 3), [])
        XCTAssertEqual(CSVFill.fill(seed: ["1"], length: 0), [])
    }
}
