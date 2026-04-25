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
}
