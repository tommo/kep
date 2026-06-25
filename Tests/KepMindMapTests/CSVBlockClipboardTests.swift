import XCTest
@testable import KepCSV

final class CSVBlockClipboardTests: XCTestCase {

    private let grid = [
        ["a", "b", "c"],
        ["d", "e", "f"],
        ["g", "h", "i"],
    ]

    // MARK: - CSVBlock.extract

    func testExtractContiguousRectangle() {
        let cells = [(0, 0), (0, 1), (1, 0), (1, 1)].map { (row: $0.0, column: $0.1) }
        let block = CSVBlock.extract(from: grid, cells: cells)
        XCTAssertEqual(block.cells, [["a", "b"], ["d", "e"]])
        XCTAssertEqual(block.height, 2)
        XCTAssertEqual(block.width, 2)
    }

    func testExtractSparseFillsGapsToPreserveAlignment() {
        // Select (0,0) and (1,2): bounding rect is 2x3, gaps become "".
        let cells = [(row: 0, column: 0), (row: 1, column: 2)]
        let block = CSVBlock.extract(from: grid, cells: cells)
        XCTAssertEqual(block.cells, [["a", "", ""], ["", "", "f"]])
    }

    func testExtractEmptySelection() {
        let block = CSVBlock.extract(from: grid, cells: [])
        XCTAssertTrue(block.isEmpty)
        XCTAssertEqual(block.height, 0)
    }

    // MARK: - CSVClipboard round-trip

    func testSerializeSingleCellIsBareValue() {
        XCTAssertEqual(CSVClipboard.serialize(CSVBlock(cells: [["hello"]])), "hello")
    }

    func testSerializeMultiCellIsTabAndNewlineJoined() {
        let block = CSVBlock(cells: [["a", "b"], ["c", "d"]])
        XCTAssertEqual(CSVClipboard.serialize(block), "a\tb\nc\td")
    }

    func testRoundTripPreservesTabsNewlinesQuotesAndCommas() {
        let tricky = CSVBlock(cells: [
            ["plain", "has,comma"],
            ["has\ttab", "has\nnewline"],
            ["\"quoted\"", "trailing\""],
        ])
        let wire = CSVClipboard.serialize(tricky)
        let back = CSVClipboard.parse(wire)
        XCTAssertEqual(back, tricky, "block must survive a serialize→parse round trip")
    }

    func testParseExternalExcelTSV() {
        // Plain tab-separated, no quoting (what Excel/Numbers emit).
        let block = CSVClipboard.parse("x\ty\tz\n1\t2\t3")
        XCTAssertEqual(block.cells, [["x", "y", "z"], ["1", "2", "3"]])
    }

    func testParseExternalCommaCSVSplitsIntoColumns() {
        // No tab present → fall back to comma separator so external CSV /
        // comma-exported Excel lands in columns (R5).
        let block = CSVClipboard.parse("a,b,c\nd,e,f")
        XCTAssertEqual(block.cells, [["a", "b", "c"], ["d", "e", "f"]])
    }

    func testInternalSingleColumnCommaCellRoundTrips() {
        // A 1-column block whose cell has a comma: serialize quotes it, so the
        // comma-fallback parse keeps it as ONE cell, not split (the R5 trap).
        let block = CSVBlock(cells: [["a,b"], ["c,d"]])
        let wire = CSVClipboard.serialize(block)
        XCTAssertEqual(CSVClipboard.parse(wire), block)
    }

    func testQuotedCommaInExternalCSVStaysOneField() {
        let block = CSVClipboard.parse("\"a,b\",c")
        XCTAssertEqual(block.cells, [["a,b", "c"]])
    }

    func testParseBlankOrSeparatorsYieldsEmptyBlock() {
        XCTAssertTrue(CSVClipboard.parse("").isEmpty)
        XCTAssertTrue(CSVClipboard.parse("   \n\t").isEmpty)
    }

    func testCommaIsQuotedInSerialize() {
        // A comma-bearing cell is quoted so the comma-fallback parser can't
        // mis-split it when the block has no tab (R5 round-trip safety).
        XCTAssertEqual(CSVClipboard.serialize(CSVBlock(cells: [["a,b"]])), "\"a,b\"")
    }
}
