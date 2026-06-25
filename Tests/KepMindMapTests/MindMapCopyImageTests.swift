import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// C1 — copy the mindmap to the clipboard as PNG / SVG (mindolph
/// doExportToClipboard parity). Uses a private NSPasteboard so the tests
/// don't clobber the user's real clipboard.
@MainActor
final class MindMapCopyImageTests: XCTestCase {

    private func scratchPasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("kep.test.\(UUID().uuidString)"))
    }

    private func sampleMap() -> MindMap {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "Alpha")
        _ = a.addChild(text: "Alpha-1")
        _ = root.addChild(text: "Beta")
        return map
    }

    func testCopyPNGPutsImageDataOnPasteboard() {
        let pb = scratchPasteboard()
        let ok = MindMapImageExport.copyPNGToPasteboard(sampleMap(), pasteboard: pb)
        XCTAssertTrue(ok)
        XCTAssertNotNil(pb.data(forType: .png), "PNG flavor present")
        XCTAssertNotNil(pb.data(forType: .tiff), "TIFF flavor present for older consumers")
        // The PNG data should decode back to a non-empty image.
        if let png = pb.data(forType: .png), let img = NSImage(data: png) {
            XCTAssertGreaterThan(img.size.width, 0)
            XCTAssertGreaterThan(img.size.height, 0)
        } else {
            XCTFail("PNG data did not decode to an image")
        }
    }

    func testCopySVGPutsStringAndDataOnPasteboard() {
        let pb = scratchPasteboard()
        let ok = MindMapImageExport.copySVGToPasteboard(sampleMap(), pasteboard: pb)
        XCTAssertTrue(ok)
        let svg = pb.string(forType: .string)
        XCTAssertNotNil(svg)
        XCTAssertTrue(svg?.contains("<svg") ?? false, "string flavor is real SVG markup")
        XCTAssertTrue(svg?.contains("Alpha") ?? false, "topic text made it into the SVG")
        XCTAssertNotNil(pb.data(forType: NSPasteboard.PasteboardType("public.svg-image")),
                        "svg-image data flavor present")
    }

    func testCopyBareRootStillRenders() {
        // A lone root (empty text, no children) still draws a box, so copy
        // succeeds rather than reporting "nothing to render". Guards against a
        // crash/false-negative on a near-empty map.
        let map = MindMap(); map.root = Topic(text: "")
        let pb = scratchPasteboard()
        XCTAssertTrue(MindMapImageExport.copySVGToPasteboard(map, pasteboard: pb))
    }
}
