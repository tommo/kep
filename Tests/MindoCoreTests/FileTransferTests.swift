import XCTest
@testable import MindoCore

final class FileTransferTests: XCTestCase {

    private let dir = URL(fileURLWithPath: "/ws/folder")

    func testNoCollisionKeepsOriginalName() {
        let url = FileTransfer.destinationURL(forItemNamed: "notes.md", in: dir, exists: { _ in false })
        XCTAssertEqual(url, dir.appendingPathComponent("notes.md"))
    }

    func testCollisionUsesCopySuffix() {
        let taken: Set<String> = ["/ws/folder/notes.md"]
        let url = FileTransfer.destinationURL(forItemNamed: "notes.md", in: dir,
                                              exists: { taken.contains($0.path) })
        XCTAssertEqual(url.lastPathComponent, "notes copy.md")
    }

    func testSecondCollisionIncrementsCopyNumber() {
        let taken: Set<String> = ["/ws/folder/notes.md", "/ws/folder/notes copy.md"]
        let url = FileTransfer.destinationURL(forItemNamed: "notes.md", in: dir,
                                              exists: { taken.contains($0.path) })
        XCTAssertEqual(url.lastPathComponent, "notes copy 2.md")
    }

    func testExtensionlessName() {
        let taken: Set<String> = ["/ws/folder/README"]
        let url = FileTransfer.destinationURL(forItemNamed: "README", in: dir,
                                              exists: { taken.contains($0.path) })
        XCTAssertEqual(url.lastPathComponent, "README copy")
    }

    // MARK: - move validation

    func testMoveIntoSameParentIsRedundant() {
        let src = URL(fileURLWithPath: "/ws/folder/notes.md")
        XCTAssertTrue(FileTransfer.isRedundantOrInvalidMove(source: src, intoDirectory: dir))
    }

    func testMoveIntoDifferentFolderIsAllowed() {
        let src = URL(fileURLWithPath: "/ws/folder/notes.md")
        let other = URL(fileURLWithPath: "/ws/other")
        XCTAssertFalse(FileTransfer.isRedundantOrInvalidMove(source: src, intoDirectory: other))
    }

    func testMoveFolderIntoItselfIsBlocked() {
        let folder = URL(fileURLWithPath: "/ws/projects")
        XCTAssertTrue(FileTransfer.isRedundantOrInvalidMove(source: folder, intoDirectory: folder))
    }

    func testMoveFolderIntoOwnDescendantIsBlocked() {
        let folder = URL(fileURLWithPath: "/ws/projects")
        let child = URL(fileURLWithPath: "/ws/projects/sub")
        XCTAssertTrue(FileTransfer.isRedundantOrInvalidMove(source: folder, intoDirectory: child))
    }

    func testSimilarlyNamedSiblingFolderNotTreatedAsDescendant() {
        // /ws/projects must NOT be considered an ancestor of /ws/projects-2.
        let folder = URL(fileURLWithPath: "/ws/projects")
        let sibling = URL(fileURLWithPath: "/ws/projects-2")
        XCTAssertFalse(FileTransfer.isRedundantOrInvalidMove(source: folder, intoDirectory: sibling))
    }
}
