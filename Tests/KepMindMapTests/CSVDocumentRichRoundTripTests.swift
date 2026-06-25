import XCTest
@testable import KepCSV

/// RFC-4180 round-trip fidelity for the on-disk .csv codec
/// (CSVDocument.parse / serialize) with rich, escaping-sensitive content:
/// embedded commas, doubled quotes, multi-line fields, Unicode, and empty
/// cells. serialize → parse must recover the exact grid.
final class CSVDocumentRichRoundTripTests: XCTestCase {

    private func roundTrip(_ rows: [[String]]) -> [[String]] {
        let doc = CSVDocument(rows: rows, hasHeader: false)
        return CSVDocument.parse(doc.serialize(), hasHeader: false).rows
    }

    func testCommaInFieldIsQuotedAndRecovered() {
        let rows = [["a,b", "c"], ["d", "e,f,g"]]
        XCTAssertEqual(roundTrip(rows), rows)
    }

    func testEmbeddedQuotesAreDoubledAndRecovered() {
        let rows = [["say \"hi\"", "plain"], ["\"lead", "trail\""]]
        XCTAssertEqual(roundTrip(rows), rows)
    }

    func testEmbeddedNewlineFieldRoundTrips() {
        let rows = [["line1\nline2", "x"], ["y", "a\nb\nc"]]
        XCTAssertEqual(roundTrip(rows), rows, "a quoted multi-line cell survives")
    }

    func testUnicodeContentRoundTrips() {
        let rows = [["café ☕️", "日本語"], ["emoji 😀🎉", "Ω≈ç√"]]
        XCTAssertEqual(roundTrip(rows), rows)
    }

    func testEmptyCellsAndRowsRoundTrip() {
        let rows = [["", "b", ""], ["", "", ""], ["x", "", "z"]]
        XCTAssertEqual(roundTrip(rows), rows)
    }

    func testCombinedNastyField() {
        let rows = [["has,comma \"and quote\"\nand newline", "next"]]
        XCTAssertEqual(roundTrip(rows), rows, "all three special cases in one cell")
    }

    // MARK: - Parser robustness on raw input

    func testParsesCRLFLineEndings() {
        let doc = CSVDocument.parse("a,b\r\nc,d\r\n", hasHeader: false)
        XCTAssertEqual(doc.rows, [["a", "b"], ["c", "d"]])
    }

    func testParsesQuotedFieldWithCommaFromRawText() {
        let doc = CSVDocument.parse("\"a,b\",c\n", hasHeader: false)
        XCTAssertEqual(doc.rows, [["a,b", "c"]])
    }

    func testParsesDoubledQuotesFromRawText() {
        let doc = CSVDocument.parse("\"she said \"\"hi\"\"\",x\n", hasHeader: false)
        XCTAssertEqual(doc.rows, [["she said \"hi\"", "x"]])
    }

    func testRaggedRowsAreNormalizedToWidestRow() {
        // Short rows get padded so the grid is rectangular.
        let doc = CSVDocument.parse("a,b,c\nd\ne,f\n", hasHeader: false)
        XCTAssertEqual(doc.columnCount, 3)
        XCTAssertEqual(doc.rows, [["a", "b", "c"], ["d", "", ""], ["e", "f", ""]])
    }

    func testSerializeEndsWithSingleTrailingNewline() {
        let doc = CSVDocument(rows: [["a", "b"]], hasHeader: false)
        XCTAssertEqual(doc.serialize(), "a,b\n")
    }

    func testEmptyDocumentRoundTrips() {
        let doc = CSVDocument.parse("", hasHeader: false)
        XCTAssertEqual(doc.rows, [[""]], "empty input yields a single empty cell")
        XCTAssertEqual(CSVDocument.parse(doc.serialize(), hasHeader: false).rows, [[""]])
    }
}
