import XCTest
@testable import KepCore

final class RelativePathTests: XCTestCase {

    private func u(_ p: String) -> URL { URL(fileURLWithPath: p) }

    func testSameDirectory() {
        XCTAssertEqual(RelativePath.from(fileAt: u("/ws/doc.md"), to: u("/ws/img.png")), "img.png")
    }

    func testSubdirectory() {
        XCTAssertEqual(RelativePath.from(fileAt: u("/ws/doc.md"), to: u("/ws/assets/img.png")), "assets/img.png")
    }

    func testParentAndSiblingTree() {
        XCTAssertEqual(RelativePath.from(fileAt: u("/ws/a/doc.md"), to: u("/ws/img.png")), "../img.png")
        XCTAssertEqual(RelativePath.from(fileAt: u("/ws/a/b/doc.md"), to: u("/ws/x/y/img.png")), "../../x/y/img.png")
    }

    func testNoCommonRootFallsBackToAbsolute() {
        XCTAssertEqual(RelativePath.from(fileAt: u("/Users/me/doc.md"), to: u("/Volumes/ext/img.png")),
                       "/Volumes/ext/img.png")
    }
}
