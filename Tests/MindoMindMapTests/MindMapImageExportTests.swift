import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

@MainActor
final class MindMapImageExportTests: XCTestCase {

    private func sampleMap() -> MindMap {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "Alpha")
        _ = a.addChild(text: "A1")
        _ = root.addChild(text: "Beta")
        return map
    }

    func testPngExportProducesNonEmptyFile() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mindo-png-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try MindMapImageExport.exportPNG(sampleMap(), to: tmp)
        let data = try Data(contentsOf: tmp)
        XCTAssertGreaterThan(data.count, 100, "PNG should have real bytes")
        // PNG magic: 89 50 4E 47 0D 0A 1A 0A
        XCTAssertEqual(data.prefix(8), Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
    }

    func testSvgExportProducesValidXMLDocument() throws {
        let svg = try MindMapImageExport.makeSVG(map: sampleMap())
        XCTAssertTrue(svg.hasPrefix("<?xml"))
        XCTAssertTrue(svg.contains("<svg "))
        XCTAssertTrue(svg.contains("</svg>"))
        // Each topic should appear as a <text> element.
        XCTAssertTrue(svg.contains(">Root<"))
        XCTAssertTrue(svg.contains(">Alpha<"))
        XCTAssertTrue(svg.contains(">A1<"))
        XCTAssertTrue(svg.contains(">Beta<"))
        // Connectors should emit at least one <path>.
        XCTAssertTrue(svg.contains("<path "))
        // Background rect uses the theme's paper color.
        XCTAssertTrue(svg.contains("<rect "))
    }

    func testSvgEscapesSpecialCharactersInTopicText() throws {
        let map = MindMap()
        let root = Topic(text: "<safe & sound>")
        map.root = root
        let svg = try MindMapImageExport.makeSVG(map: map)
        XCTAssertTrue(svg.contains("&lt;safe &amp; sound&gt;"))
        XCTAssertFalse(svg.contains(">< safe"), "raw < should not leak in")
    }

    func testThrowsNoContentForEmptyMap() {
        let map = MindMap()
        XCTAssertThrowsError(try MindMapImageExport.makeSVG(map: map)) { error in
            guard case MindMapImageExport.ExportError.noContent = error else {
                XCTFail("expected .noContent, got \(error)")
                return
            }
        }
    }
}
