import XCTest
import AppKit
@testable import KepMindMap

final class MindMapPasteHelperTests: XCTestCase {

    /// Make a 1×1 PNG so the tests don't depend on any disk fixture.
    private func makeTinyPNG() -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32
        )!
        return bitmap.representation(using: .png, properties: [:])!
    }

    func testReadsBase64FromDirectPNGData() {
        let pb = NSPasteboard(name: NSPasteboard.Name("MindMapPasteHelperTests-PNG-\(UUID())"))
        pb.clearContents()
        let png = makeTinyPNG()
        pb.setData(png, forType: .png)
        XCTAssertEqual(MindMapPasteHelper.imageBase64(from: pb), png.base64EncodedString())
    }

    func testReadsBase64FromTIFFViaNSImageRoundTrip() {
        let pb = NSPasteboard(name: NSPasteboard.Name("MindMapPasteHelperTests-TIFF-\(UUID())"))
        pb.clearContents()
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32
        )!
        // TIFF, not PNG — exercises the NSImage decode → re-encode fallback.
        let tiff = bitmap.tiffRepresentation!
        pb.setData(tiff, forType: .tiff)
        let result = MindMapPasteHelper.imageBase64(from: pb)
        XCTAssertNotNil(result)
        // Round-tripped bytes should still parse as a PNG.
        let decoded = Data(base64Encoded: result ?? "")
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.prefix(8),
                       Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
                       "fallback path must always emit PNG magic")
    }

    func testReturnsNilForEmptyPasteboard() {
        let pb = NSPasteboard(name: NSPasteboard.Name("MindMapPasteHelperTests-Empty-\(UUID())"))
        pb.clearContents()
        XCTAssertNil(MindMapPasteHelper.imageBase64(from: pb))
    }

    func testReturnsNilForTextOnlyPasteboard() {
        let pb = NSPasteboard(name: NSPasteboard.Name("MindMapPasteHelperTests-Text-\(UUID())"))
        pb.clearContents()
        pb.setString("hello", forType: .string)
        XCTAssertNil(MindMapPasteHelper.imageBase64(from: pb))
    }

    // MARK: - smartTextSubtree

    func testSmartTextSingleLineYieldsOneTopic() {
        let topic = MindMapPasteHelper.smartTextSubtree("Hello")
        XCTAssertEqual(topic?.text, "Hello")
        XCTAssertEqual(topic?.children.count, 0)
    }

    func testSmartTextMultilineBuildsHierarchy() {
        let text = """
        Section
          A
          B
        """
        let topic = MindMapPasteHelper.smartTextSubtree(text)
        XCTAssertEqual(topic?.text, "Section")
        XCTAssertEqual(topic?.children.map(\.text), ["A", "B"])
    }

    func testSmartTextStripsBulletMarkers() {
        // - / * / • / + are accepted bullet markers (TextOutlineImporter
        // contract) — verify the smart-paste path forwards that.
        let text = """
        Top
          - first
          * second
        """
        let topic = MindMapPasteHelper.smartTextSubtree(text)
        XCTAssertEqual(topic?.children.map(\.text), ["first", "second"])
    }

    func testSmartTextEmptyOrWhitespaceReturnsNil() {
        XCTAssertNil(MindMapPasteHelper.smartTextSubtree(""))
        XCTAssertNil(MindMapPasteHelper.smartTextSubtree("   "))
        XCTAssertNil(MindMapPasteHelper.smartTextSubtree("\n\n  \n"))
    }

    func testSmartTextSubtreeIsDetached() {
        // The returned subtree must be ungrafted (parent / map nil) so
        // undoableReparent can plug it into the live mindmap cleanly.
        let topic = MindMapPasteHelper.smartTextSubtree("Standalone")
        XCTAssertNil(topic?.parent)
        XCTAssertNil(topic?.map)
    }
}
