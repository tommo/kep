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
        XCTAssertEqual(BranchExportFormat.text.fileExtension, "txt")
    }
}
