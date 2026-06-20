import XCTest
@testable import MindoCSV

/// The CSV "extended layer": A1 cell-ref math and the sidecar (formulas +
/// styling) that keeps the `.csv` itself plain and merge-friendly.
final class CSVSheetExtrasTests: XCTestCase {

    // MARK: - Cell refs

    func testA1RoundTrip() {
        for a1 in ["A1", "B3", "Z1", "AA1", "AB27", "BA100"] {
            XCTAssertEqual(CSVCellRef(a1: a1)?.a1, a1, "round-trip \(a1)")
        }
    }

    func testA1ToCoord() {
        XCTAssertEqual(CSVCellRef(a1: "A1"), CSVCellRef(row: 0, col: 0))
        XCTAssertEqual(CSVCellRef(a1: "B3"), CSVCellRef(row: 2, col: 1))
        XCTAssertEqual(CSVCellRef(a1: "AA1"), CSVCellRef(row: 0, col: 26))
        XCTAssertEqual(CSVCellRef(a1: "$C$5"), CSVCellRef(row: 4, col: 2))   // absolute markers ignored
    }

    func testColumnLabels() {
        XCTAssertEqual(CSVCellRef.columnLabel(0), "A")
        XCTAssertEqual(CSVCellRef.columnLabel(25), "Z")
        XCTAssertEqual(CSVCellRef.columnLabel(26), "AA")
        XCTAssertEqual(CSVCellRef.columnIndex("A"), 0)
        XCTAssertEqual(CSVCellRef.columnIndex("AA"), 26)
        XCTAssertNil(CSVCellRef.columnIndex("A1"))
    }

    func testMalformedRefs() {
        XCTAssertNil(CSVCellRef(a1: "1A"))
        XCTAssertNil(CSVCellRef(a1: "A"))
        XCTAssertNil(CSVCellRef(a1: "5"))
        XCTAssertNil(CSVCellRef(a1: "A0"))
        XCTAssertNil(CSVCellRef(a1: ""))
    }

    func testRangeExpansion() {
        XCTAssertEqual(CSVCellRef.parseRange("A1:A3")?.map(\.a1), ["A1", "A2", "A3"])
        XCTAssertEqual(CSVCellRef.parseRange("A1:B2")?.map(\.a1), ["A1", "B1", "A2", "B2"])
        XCTAssertEqual(CSVCellRef.parseRange("A1")?.map(\.a1), ["A1"])
        // reversed endpoints normalize
        XCTAssertEqual(CSVCellRef.parseRange("B2:A1")?.map(\.a1), ["A1", "B1", "A2", "B2"])
        XCTAssertNil(CSVCellRef.parseRange("A1:")?.map(\.a1))
    }

    // MARK: - Sidecar

    func testSidecarPath() {
        let csv = URL(fileURLWithPath: "/ws/notes.csv")
        // Hidden dotfile so the extended layer doesn't clutter the workspace.
        XCTAssertEqual(CSVSheetExtras.sidecarURL(for: csv).lastPathComponent, ".notes.csv.sheet.json")
        // Legacy (pre-dotfile) name, kept for read + cleanup migration.
        XCTAssertEqual(CSVSheetExtras.legacySidecarURL(for: csv).lastPathComponent, "notes.csv.sheet.json")
    }

    func testStyleDropsEmpty() {
        var extras = CSVSheetExtras()
        extras.setStyle(CSVCellStyle(bold: true), at: "A1")
        extras.setStyle(CSVCellStyle(), at: "A1")            // empty → removed
        XCTAssertTrue(extras.styles.isEmpty)
        extras.setFormula("=B1*2", at: "C1")
        extras.setFormula(nil, at: "C1")                      // nil → removed
        XCTAssertTrue(extras.formulas.isEmpty)
        extras.setFormula("plain text", at: "C1")             // not a formula → ignored
        XCTAssertTrue(extras.formulas.isEmpty)
    }

    func testSidecarRoundTrip() throws {
        var extras = CSVSheetExtras()
        extras.setFormula("=SUM(A1:A10)", at: "A11")
        extras.setFormula("=B1*2", at: "C1")
        extras.setStyle(CSVCellStyle(bold: true, background: "#f0f0f0"), at: "A1")
        extras.setStyle(CSVCellStyle(italic: true, align: "right"), at: "B2")

        let json = extras.serialize()
        let back = try XCTUnwrap(CSVSheetExtras.parse(json))
        XCTAssertEqual(back, extras)
    }

    /// Serialization is deterministic (sorted, stable) — the property that makes
    /// the sidecar merge cleanly in version control.
    func testSerializationIsDeterministicAndSorted() {
        var a = CSVSheetExtras()
        a.setFormula("=1", at: "C1"); a.setFormula("=2", at: "A1"); a.setFormula("=3", at: "B1")
        var b = CSVSheetExtras()
        b.setFormula("=3", at: "B1"); b.setFormula("=2", at: "A1"); b.setFormula("=1", at: "C1")
        XCTAssertEqual(a.serialize(), b.serialize(), "insertion order must not affect output")
        // A1 sorts before B1 before C1 in the emitted JSON.
        let s = a.serialize()
        XCTAssertLessThan(s.range(of: "\"A1\"")!.lowerBound, s.range(of: "\"B1\"")!.lowerBound)
        XCTAssertLessThan(s.range(of: "\"B1\"")!.lowerBound, s.range(of: "\"C1\"")!.lowerBound)
    }

    func testEmptyExtras() {
        XCTAssertTrue(CSVSheetExtras().isEmpty)
        var e = CSVSheetExtras(); e.setFormula("=A1", at: "B1")
        XCTAssertFalse(e.isEmpty)
    }
}
