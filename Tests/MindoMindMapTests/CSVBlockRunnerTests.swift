import XCTest
@testable import MindoCSV

/// Sheet blocks: Lua computations over the table, with a name that's
/// referenceable from formulas. Covers the runner's sheet API + sidecar.
final class CSVBlockRunnerTests: XCTestCase {

    private func doc() -> CSVDocument {
        // header + 3 body rows; column A = Qty (numbers), B = Status (text)
        CSVDocument(rows: [["Qty", "Status"], ["10", "ok"], ["20", "fail"], ["30", "ok"]],
                    hasHeader: true)
    }

    func testSumColumnByLetterAndHeader() {
        let r = CSVBlockRunner.run([
            CSVEvalBlock(name: "byLetter", source: #"return sum(col("A"))"#),
            CSVEvalBlock(name: "byHeader", source: #"return sum(col("Qty"))"#),
        ], over: doc())
        XCTAssertEqual(r.map(\.value), ["60", "60"])
        XCTAssertNil(r[0].error); XCTAssertNil(r[1].error)
    }

    func testCellAndAggregates() {
        let r = CSVBlockRunner.run([
            CSVEvalBlock(name: "b2", source: #"return cell("A2")"#),       // first body cell = 10
            CSVEvalBlock(name: "rowsN", source: "return nrows()"),
            CSVEvalBlock(name: "med", source: #"return median(col("Qty"))"#),
            CSVEvalBlock(name: "avg", source: #"return avg(col("A"))"#),
        ], over: doc())
        XCTAssertEqual(r.map(\.value), ["10", "3", "20", "20"])
    }

    func testRowsAndPrint() {
        let r = CSVBlockRunner.run([
            CSVEvalBlock(name: "fails", source: """
                local n = 0
                for _, row in ipairs(rows()) do if row.Status == "fail" then n = n + 1 end end
                print("checked", #rows())
                return n
                """),
        ], over: doc())
        XCTAssertEqual(r[0].value, "1")
        XCTAssertEqual(r[0].output, "checked\t3\n")
    }

    func testLaterBlockUsesEarlierGlobal() {
        let r = CSVBlockRunner.run([
            CSVEvalBlock(name: "total", source: #"return sum(col("A"))"#),
            CSVEvalBlock(name: "withTax", source: "return total * 1.1"),
        ], over: doc())
        XCTAssertEqual(r[0].value, "60")
        XCTAssertEqual(r[1].value, "66")
    }

    func testErrorIsCaptured() {
        let r = CSVBlockRunner.run([CSVEvalBlock(name: "bad", source: "return nope(")], over: doc())
        XCTAssertNotNil(r[0].error)
        XCTAssertEqual(r[0].value, "")
    }

    // MARK: - Sidecar

    func testBlocksRoundTripInSidecar() {
        var extras = CSVSheetExtras(formulas: ["A1": "=1+1"],
                                    blocks: [CSVEvalBlock(id: "x", name: "total",
                                                          source: "return sum(col(\"A\"))", output: "60")])
        XCTAssertFalse(extras.isEmpty)
        let parsed = CSVSheetExtras.parse(extras.serialize())
        XCTAssertEqual(parsed, extras)
        XCTAssertEqual(parsed?.blocks.first?.name, "total")
    }

    func testOldSidecarWithoutBlocksStillParses() {
        // A sidecar written before `blocks` existed must still decode (→ []).
        let legacy = #"{"version":1,"formulas":{"A1":"=2+2"},"styles":{}}"#
        let parsed = CSVSheetExtras.parse(legacy)
        XCTAssertEqual(parsed?.formulas["A1"], "=2+2")
        XCTAssertEqual(parsed?.blocks, [])
    }
}
