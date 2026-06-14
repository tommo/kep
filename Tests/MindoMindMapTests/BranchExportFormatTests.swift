import XCTest
import MindoModel
@testable import MindoMindMap

final class BranchExportFormatTests: XCTestCase {

    private func branch() -> MindMap {
        let map = MindMap()
        let root = Topic(text: "Project"); map.root = root
        let a = root.addChild(text: "Alpha")
        _ = a.addChild(text: "Alpha detail")
        _ = root.addChild(text: "Beta")
        return map
    }

    // MARK: - Shared export(_:) + clipboard subset (C4)

    func testMarkdownExportContainsTopics() {
        let md = BranchExportFormat.markdown.export(branch())
        XCTAssertTrue(md.contains("Project") && md.contains("Alpha") && md.contains("Beta"))
    }

    func testTextOrgAsciidocAllProduceNonEmptyTextWithTopics() {
        for fmt in [BranchExportFormat.text, .orgMode, .asciidoc] {
            let body = fmt.export(branch())
            XCTAssertFalse(body.isEmpty, "\(fmt) produced empty output")
            XCTAssertTrue(body.contains("Alpha"), "\(fmt) dropped a topic")
        }
    }

    func testMmdExportMentionsRoot() {
        XCTAssertTrue(BranchExportFormat.mindmap.export(branch()).contains("Project"))
    }

    func testClipboardFormatsAreTextFriendlySubset() {
        XCTAssertEqual(BranchExportFormat.clipboardFormats, [.markdown, .text, .asciidoc, .orgMode])
        for fileOnly in [BranchExportFormat.mindmap, .freemind, .mindmup] {
            XCTAssertFalse(BranchExportFormat.clipboardFormats.contains(fileOnly),
                           "\(fileOnly) is file-only and shouldn't be a clipboard option")
        }
    }

    // MARK: - Existing extension / title coverage

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
