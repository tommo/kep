import XCTest
import KepMarkdown

final class MimeTypeTests: XCTestCase {

    func testKnownImageExtensions() {
        XCTAssertEqual(MarkdownEditor.Coordinator.mimeType(for: "png"), "image/png")
        XCTAssertEqual(MarkdownEditor.Coordinator.mimeType(for: "jpg"), "image/jpeg")
        XCTAssertEqual(MarkdownEditor.Coordinator.mimeType(for: "jpeg"), "image/jpeg")
        XCTAssertEqual(MarkdownEditor.Coordinator.mimeType(for: "gif"), "image/gif")
        XCTAssertEqual(MarkdownEditor.Coordinator.mimeType(for: "svg"), "image/svg+xml")
        XCTAssertEqual(MarkdownEditor.Coordinator.mimeType(for: "webp"), "image/webp")
    }

    func testUnknownExtensionFallsBackToOctetStream() {
        XCTAssertEqual(MarkdownEditor.Coordinator.mimeType(for: "wat"), "application/octet-stream")
        XCTAssertEqual(MarkdownEditor.Coordinator.mimeType(for: ""), "application/octet-stream")
    }
}
