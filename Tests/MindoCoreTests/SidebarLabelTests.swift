import XCTest
@testable import MindoCore

final class SidebarLabelTests: XCTestCase {

    // MARK: - stripExtension

    func testStripsCommonExtensions() {
        XCTAssertEqual(SidebarLabel.stripExtension("notes.mmd"), "notes")
        XCTAssertEqual(SidebarLabel.stripExtension("readme.md"), "readme")
        XCTAssertEqual(SidebarLabel.stripExtension("diagram.puml"), "diagram")
        XCTAssertEqual(SidebarLabel.stripExtension("data.csv"), "data")
    }

    func testKeepsNameWithoutExtension() {
        XCTAssertEqual(SidebarLabel.stripExtension("README"), "README")
        XCTAssertEqual(SidebarLabel.stripExtension("Makefile"), "Makefile")
    }

    func testStripsOnlyTheLastSegment() {
        // tar.gz / d.ts — only the last segment goes; the rest is part
        // of the visible identifier (e.g. an "archive.tar" rename to
        // "archive" loses meaningful context).
        XCTAssertEqual(SidebarLabel.stripExtension("archive.tar.gz"), "archive.tar")
        XCTAssertEqual(SidebarLabel.stripExtension("types.d.ts"), "types.d")
    }

    func testKeepsLeadingDotForDotfiles() {
        // `.gitignore` has no trailing extension — the leading dot is
        // part of the file's identity, not an extension marker.
        XCTAssertEqual(SidebarLabel.stripExtension(".gitignore"), ".gitignore")
        XCTAssertEqual(SidebarLabel.stripExtension(".env"), ".env")
    }

    func testStripsExtensionFromDottedDotfile() {
        // `.config.local` — the trailing `.local` IS the extension by
        // pathExtension semantics. Strip it.
        XCTAssertEqual(SidebarLabel.stripExtension(".config.local"), ".config")
    }

    func testHandlesEdgeCases() {
        XCTAssertEqual(SidebarLabel.stripExtension(""), "")
        XCTAssertEqual(SidebarLabel.stripExtension("."), ".")
        XCTAssertEqual(SidebarLabel.stripExtension(".."), "..")
    }

    func testKeepsNamesWithEmbeddedSpaces() {
        XCTAssertEqual(SidebarLabel.stripExtension("My File.mmd"), "My File")
    }

    // MARK: - displayName

    func testDisplayNameOffPassesThrough() {
        XCTAssertEqual(
            SidebarLabel.displayName("notes.mmd", hideExtensions: false),
            "notes.mmd"
        )
    }

    func testDisplayNameOnStrips() {
        XCTAssertEqual(
            SidebarLabel.displayName("notes.mmd", hideExtensions: true),
            "notes"
        )
    }
}
