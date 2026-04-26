import XCTest
@testable import MindoMindMap

final class BranchExportFormatTests: XCTestCase {

    func testEveryFormatHasUniqueExtension() {
        let exts = BranchExportFormat.allCases.map(\.fileExtension)
        XCTAssertEqual(Set(exts).count, exts.count, "extensions must be unique: \(exts)")
    }

    func testEveryFormatHasNonEmptyMenuTitle() {
        for fmt in BranchExportFormat.allCases {
            XCTAssertFalse(fmt.menuTitle.isEmpty, "format \(fmt) needs a menu title")
        }
    }

    func testExtensionsMatchFamiliarTypes() {
        XCTAssertEqual(BranchExportFormat.mindmap.fileExtension, "mmd")
        XCTAssertEqual(BranchExportFormat.orgMode.fileExtension, "org")
        XCTAssertEqual(BranchExportFormat.freemind.fileExtension, "mm")
        XCTAssertEqual(BranchExportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(BranchExportFormat.asciidoc.fileExtension, "adoc")
        XCTAssertEqual(BranchExportFormat.mindmup.fileExtension, "mup")
        XCTAssertEqual(BranchExportFormat.text.fileExtension, "txt")
    }

    func testCoversEveryWholeMapExporterShipped() {
        // The Export Branch submenu should not lag behind File → Export.
        // Spell out the formats we expect so a future exporter addition
        // is reminded to plumb through here too (this is intentionally
        // a hard list — easy to update, easy to flag).
        let expected: Set<String> = ["mindmap", "orgMode", "freemind", "markdown", "asciidoc", "mindmup", "text"]
        let actual = Set(BranchExportFormat.allCases.map(\.rawValue))
        XCTAssertEqual(actual, expected)
    }
}
