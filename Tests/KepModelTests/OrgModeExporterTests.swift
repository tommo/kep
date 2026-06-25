import XCTest
@testable import KepModel

final class OrgModeExporterTests: XCTestCase {

    func testEmptyMapEmitsTitleHeaderOnly() {
        let map = MindMap()
        let out = OrgModeExporter.export(map)
        XCTAssertTrue(out.hasPrefix("#+TITLE: \n"))
        XCTAssertTrue(out.contains("#+CREATOR: Kep"))
    }

    func testRootGetsOneStarChildrenGetMore() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "Alpha")
        _ = a.addChild(text: "A1")
        _ = root.addChild(text: "Beta")

        let out = OrgModeExporter.export(map)
        XCTAssertTrue(out.contains("\n* Root\n"))
        XCTAssertTrue(out.contains("\n** Alpha\n"))
        XCTAssertTrue(out.contains("\n*** A1\n"))
        XCTAssertTrue(out.contains("\n** Beta\n"))
    }

    func testRootTitlePopulatesTitleHeader() {
        let map = MindMap()
        map.root = Topic(text: "My Map")
        let out = OrgModeExporter.export(map)
        XCTAssertTrue(out.hasPrefix("#+TITLE: My Map\n"))
    }

    func testHeadingNewlineCollapsedToSpace() {
        // Org headlines are single-line; embedded \n must collapse to a space.
        XCTAssertEqual(OrgModeExporter.escapeHeading("two\nlines"), "two lines")
    }

    func testHeadingDropsControlCharacters() {
        XCTAssertEqual(OrgModeExporter.escapeHeading("clean\u{07}text"), "cleantext")
    }

    func testNoteEmittedAsLiteralPrefixLines() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        root.setExtra(ExtraNote(text: "first\nsecond"))
        let out = OrgModeExporter.export(map)
        XCTAssertTrue(out.contains(": first\n"))
        XCTAssertTrue(out.contains(": second\n"))
    }

    func testLinkAndFileExtras() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        root.setExtra(ExtraLink(uri: "https://example.com"))
        root.setExtra(ExtraFile(uri: "/tmp/foo.txt"))
        let out = OrgModeExporter.export(map)
        XCTAssertTrue(out.contains("URL: [[https://example.com]]"))
        XCTAssertTrue(out.contains("FILE: [[/tmp/foo.txt]]"))
    }

    func testCodeSnippetsEmittedAsBeginEndSrcBlocks() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        root.putCodeSnippet(language: "swift", body: "let x = 1\n")
        let out = OrgModeExporter.export(map)
        XCTAssertTrue(out.contains("#+BEGIN_SRC swift\nlet x = 1\n#+END_SRC"))
    }
}
