import XCTest
@testable import MindoCore

final class SessionRestoreTests: XCTestCase {

    private let saved = ["/ws/a.md", "/ws/gone.md", "/ws/b.csv"]
    private func exists(_ p: String) -> Bool { p != "/ws/gone.md" }

    func testReopensExistingPathsInOrder() {
        let result = SessionRestore.pathsToReopen(savedPaths: saved, openLastFiles: true, exists: exists)
        XCTAssertEqual(result, ["/ws/a.md", "/ws/b.csv"])
    }

    func testDisabledYieldsNothing() {
        let result = SessionRestore.pathsToReopen(savedPaths: saved, openLastFiles: false, exists: exists)
        XCTAssertTrue(result.isEmpty)
    }

    func testEmptySavedList() {
        XCTAssertTrue(SessionRestore.pathsToReopen(savedPaths: [], openLastFiles: true, exists: { _ in true }).isEmpty)
    }

    func testAllMissingYieldsNothing() {
        let result = SessionRestore.pathsToReopen(savedPaths: saved, openLastFiles: true, exists: { _ in false })
        XCTAssertTrue(result.isEmpty)
    }
}
