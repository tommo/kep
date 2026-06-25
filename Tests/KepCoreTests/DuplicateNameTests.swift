import XCTest
@testable import KepCore

final class DuplicateNameTests: XCTestCase {

    private let dir = URL(fileURLWithPath: "/tmp/KepDuplicateNameTests")

    func testFirstCandidateIsCopySuffix() {
        let url = DuplicateName.uniqueURL(in: dir, stem: "notes", ext: "md", exists: { _ in false })
        XCTAssertEqual(url.lastPathComponent, "notes copy.md")
    }

    func testSecondCandidateAddsCounter() {
        let taken = Set(["notes copy.md"])
        let url = DuplicateName.uniqueURL(in: dir, stem: "notes", ext: "md",
                                          exists: { taken.contains($0.lastPathComponent) })
        XCTAssertEqual(url.lastPathComponent, "notes copy 2.md")
    }

    func testSkipsThroughManyTaken() {
        let taken = Set(["notes copy.md", "notes copy 2.md", "notes copy 3.md"])
        let url = DuplicateName.uniqueURL(in: dir, stem: "notes", ext: "md",
                                          exists: { taken.contains($0.lastPathComponent) })
        XCTAssertEqual(url.lastPathComponent, "notes copy 4.md")
    }

    func testNoExtensionDropsTrailingDot() {
        let url = DuplicateName.uniqueURL(in: dir, stem: "Folder", ext: "", exists: { _ in false })
        XCTAssertEqual(url.lastPathComponent, "Folder copy")
    }

    func testCandidateSequenceShape() {
        var iter = DuplicateName.candidateNames(stem: "x", ext: "md").makeIterator()
        XCTAssertEqual(iter.next(), "x copy.md")
        XCTAssertEqual(iter.next(), "x copy 2.md")
        XCTAssertEqual(iter.next(), "x copy 3.md")
    }

    func testIncludesParentDirectoryInResult() {
        let url = DuplicateName.uniqueURL(in: dir, stem: "f", ext: "txt", exists: { _ in false })
        XCTAssertEqual(url.deletingLastPathComponent().path, dir.path)
    }
}
