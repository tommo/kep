import XCTest
@testable import MindoCSV

final class CSVLinkTests: XCTestCase {

    private func u(_ p: String) -> URL { URL(fileURLWithPath: p) }

    func testSameDirectory() {
        let path = CSVLink.relativePath(of: u("/ws/data/files.txt"), fromFileAt: u("/ws/data/sheet.csv"))
        XCTAssertEqual(path, "files.txt")
    }

    func testSubdirectory() {
        let path = CSVLink.relativePath(of: u("/ws/data/assets/img.png"), fromFileAt: u("/ws/data/sheet.csv"))
        XCTAssertEqual(path, "assets/img.png")
    }

    func testParentDirectory() {
        let path = CSVLink.relativePath(of: u("/ws/notes/readme.md"), fromFileAt: u("/ws/data/sheet.csv"))
        XCTAssertEqual(path, "../notes/readme.md")
    }

    func testSiblingTree() {
        let path = CSVLink.relativePath(of: u("/ws/a/b/c.txt"), fromFileAt: u("/ws/x/y/sheet.csv"))
        XCTAssertEqual(path, "../../a/b/c.txt")
    }

    func testNoCommonRootFallsBackToAbsolute() {
        // Only "/" in common → absolute path, not a ../../.. chain.
        let path = CSVLink.relativePath(of: u("/Volumes/ext/file.txt"), fromFileAt: u("/Users/me/sheet.csv"))
        XCTAssertEqual(path, "/Volumes/ext/file.txt")
    }
}
