import XCTest
@testable import MindoCSV

/// CSVSheet ties the plain CSV (baked values) to the extended layer (formulas +
/// styles) and recomputes through the Lua engine. End-to-end, headless.
final class CSVSheetTests: XCTestCase {

    func testRecomputeBakesFormulaValues() {
        // Values in the grid; a formula lives only in the extended layer.
        let doc = CSVDocument(rows: [["10", "5", ""]], hasHeader: false)
        var extras = CSVSheetExtras()
        extras.setFormula("=A1*B1", at: "C1")
        let sheet = CSVSheet(document: doc, extras: extras)

        sheet.recompute()
        XCTAssertEqual(sheet.value(at: CSVCellRef(a1: "C1")!), "50")   // baked into the grid
    }

    func testBakedCSVIsPlainValuesNotFormulas() {
        let doc = CSVDocument(rows: [["10", "5", ""]], hasHeader: false)
        var extras = CSVSheetExtras()
        extras.setFormula("=A1+B1", at: "C1")
        let sheet = CSVSheet(document: doc, extras: extras)
        sheet.recompute()

        let csv = sheet.bakedCSV()
        XCTAssertTrue(csv.contains("15"), "csv holds the computed value")
        XCTAssertFalse(csv.contains("=A1"), "csv must NOT contain the formula source")
        // The formula lives only in the sidecar.
        XCTAssertTrue(sheet.sidecarJSON()?.contains("=A1+B1") ?? false)
    }

    func testEditFormulaRecomputesDependents() {
        let doc = CSVDocument(rows: [["10", "5", ""], ["", "", ""]], hasHeader: false)
        let sheet = CSVSheet(document: doc)
        sheet.setCell(CSVCellRef(a1: "C1")!, to: "=A1+B1")
        XCTAssertEqual(sheet.value(at: CSVCellRef(a1: "C1")!), "15")
        sheet.setCell(CSVCellRef(a1: "C2")!, to: "=C1*2")
        XCTAssertEqual(sheet.value(at: CSVCellRef(a1: "C2")!), "30")

        // Editing a referenced value re-bakes the dependents.
        sheet.setCell(CSVCellRef(a1: "A1")!, to: "20")
        XCTAssertEqual(sheet.value(at: CSVCellRef(a1: "C1")!), "25")
        XCTAssertEqual(sheet.value(at: CSVCellRef(a1: "C2")!), "50")
    }

    func testSetLiteralClearsFormula() {
        let doc = CSVDocument(rows: [["10", "5", ""]], hasHeader: false)
        let sheet = CSVSheet(document: doc)
        sheet.setCell(CSVCellRef(a1: "C1")!, to: "=A1+B1")
        XCTAssertNotNil(sheet.formula(at: CSVCellRef(a1: "C1")!))
        sheet.setCell(CSVCellRef(a1: "C1")!, to: "literal")
        XCTAssertNil(sheet.formula(at: CSVCellRef(a1: "C1")!))
        XCTAssertEqual(sheet.value(at: CSVCellRef(a1: "C1")!), "literal")
    }

    func testLoadRoundTripThroughExtendedLayer() {
        // Author a sheet, save baked csv + sidecar, reload, recompute → same.
        let doc = CSVDocument(rows: [["100", "200", ""]], hasHeader: false)
        let sheet = CSVSheet(document: doc)
        sheet.setCell(CSVCellRef(a1: "C1")!, to: "=SUM(A1:B1)")
        sheet.setStyle(CSVCellStyle(bold: true), at: CSVCellRef(a1: "A1")!)

        let csv = sheet.bakedCSV()
        let sidecar = sheet.sidecarJSON()
        XCTAssertEqual(sheet.value(at: CSVCellRef(a1: "C1")!), "300")

        let reloaded = CSVSheet.load(csv: csv, sidecar: sidecar, hasHeader: false)
        XCTAssertEqual(reloaded.formula(at: CSVCellRef(a1: "C1")!), "=SUM(A1:B1)")
        XCTAssertEqual(reloaded.style(at: CSVCellRef(a1: "A1")!)?.bold, true)
        reloaded.recompute()
        XCTAssertEqual(reloaded.value(at: CSVCellRef(a1: "C1")!), "300")
    }

    func testNoFormulasNoSidecar() {
        let sheet = CSVSheet(document: CSVDocument(rows: [["a", "b"]], hasHeader: false))
        XCTAssertNil(sheet.sidecarJSON(), "a plain CSV with no extras writes no sidecar")
        XCTAssertFalse(sheet.recompute(), "nothing to recompute")
    }
}
