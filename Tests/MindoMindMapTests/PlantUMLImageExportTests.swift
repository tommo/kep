import XCTest
@testable import MindoPlantUML

final class PlantUMLImageExportTests: XCTestCase {

    func testFileExtensions() {
        XCTAssertEqual(PlantUMLImageExport.Format.svg.fileExtension, "svg")
        XCTAssertEqual(PlantUMLImageExport.Format.png.fileExtension, "png")
    }

    func testDefaultFilenameFromSourceURL() {
        let url = URL(fileURLWithPath: "/Users/x/diagrams/flow.puml")
        XCTAssertEqual(PlantUMLImageExport.defaultFilename(sourceURL: url, format: .svg), "flow.svg")
        XCTAssertEqual(PlantUMLImageExport.defaultFilename(sourceURL: url, format: .png), "flow.png")
    }

    func testDefaultFilenameFallsBackForUnsavedDoc() {
        XCTAssertEqual(PlantUMLImageExport.defaultFilename(sourceURL: nil, format: .svg), "diagram.svg")
        XCTAssertEqual(PlantUMLImageExport.defaultFilename(sourceURL: nil, format: .png), "diagram.png")
    }

    func testSVGDataPassesThroughUnchanged() {
        let svg = Data("<svg/>".utf8)
        XCTAssertEqual(PlantUMLImageExport.data(forSVG: svg, format: .svg), svg)
    }

    func testNilOrEmptySVGYieldsNoData() {
        XCTAssertNil(PlantUMLImageExport.data(forSVG: nil, format: .svg))
        XCTAssertNil(PlantUMLImageExport.data(forSVG: Data(), format: .png))
    }

    func testPNGFromGarbageDataIsNil() {
        // Not a renderable image -> nil, never a corrupt file.
        XCTAssertNil(PlantUMLImageExport.pngData(fromSVGData: Data([0x00, 0x01, 0x02, 0x03])))
        XCTAssertNil(PlantUMLImageExport.data(forSVG: Data([0xDE, 0xAD]), format: .png))
    }

    func testFormatRawValueRoundTrips() {
        // The save-panel reads the chosen extension back into a Format.
        XCTAssertEqual(PlantUMLImageExport.Format(rawValue: "svg"), .svg)
        XCTAssertEqual(PlantUMLImageExport.Format(rawValue: "png"), .png)
        XCTAssertNil(PlantUMLImageExport.Format(rawValue: "pdf"))
    }
}
