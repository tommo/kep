import XCTest
import KepMarkdown

final class MarkdownExporterTests: XCTestCase {

    func testExportHTMLWritesStyledStandaloneDocument() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("kep-md-export-\(UUID()).html")
        defer { try? FileManager.default.removeItem(at: tmp) }

        try MarkdownExporter.exportHTML(
            markdown: "# Title\n\n**bold** and `code`",
            to: tmp
        )

        let html = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(html.contains("<!doctype html>"), "should start with HTML5 doctype")
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<strong>bold</strong>"))
        XCTAssertTrue(html.contains("<code>code</code>"))
    }

    func testExportHTMLPropagatesWriteFailure() {
        // Write into a directory that doesn't exist.
        let bogus = URL(fileURLWithPath: "/var/empty/no/such/dir/file-\(UUID()).html")
        XCTAssertThrowsError(try MarkdownExporter.exportHTML(markdown: "x", to: bogus)) { err in
            guard case MarkdownExporter.ExportError.writeFailed = err else {
                XCTFail("expected .writeFailed, got \(err)")
                return
            }
        }
    }
}
