import XCTest
@testable import KepCore

final class RenamePlanTests: XCTestCase {

    /// No directory entries exist.
    private let empty: (String) -> Bool = { _ in false }

    func testEmptyOrWhitespaceIsUnchanged() {
        XCTAssertEqual(RenamePlan.resolve(current: "a.md", desired: "", exists: empty), .unchanged)
        XCTAssertEqual(RenamePlan.resolve(current: "a.md", desired: "   ", exists: empty), .unchanged)
    }

    func testSameNameIsUnchanged() {
        XCTAssertEqual(RenamePlan.resolve(current: "a.md", desired: "a.md", exists: empty), .unchanged)
        // Surrounding whitespace is trimmed before the compare.
        XCTAssertEqual(RenamePlan.resolve(current: "a.md", desired: "  a.md ", exists: empty), .unchanged)
    }

    func testFreeNameIsOK() {
        XCTAssertEqual(RenamePlan.resolve(current: "a.md", desired: "b.md", exists: empty), .ok("b.md"))
    }

    func testCollisionSuggestsSuffixPreservingExtension() {
        let taken: Set<String> = ["b.md"]
        XCTAssertEqual(
            RenamePlan.resolve(current: "a.md", desired: "b.md", exists: { taken.contains($0) }),
            .collision(requested: "b.md", suggestion: "b 2.md"))
    }

    func testCollisionSkipsExistingSuffixes() {
        let taken: Set<String> = ["b.md", "b 2.md", "b 3.md"]
        XCTAssertEqual(
            RenamePlan.resolve(current: "a.md", desired: "b.md", exists: { taken.contains($0) }),
            .collision(requested: "b.md", suggestion: "b 4.md"))
    }

    func testCollisionOnExtensionlessName() {
        let taken: Set<String> = ["Folder"]
        XCTAssertEqual(
            RenamePlan.resolve(current: "Other", desired: "Folder", exists: { taken.contains($0) }),
            .collision(requested: "Folder", suggestion: "Folder 2"))
    }

    func testUniqueNamePreservesMultiDotExtension() {
        // NSString.pathExtension only takes the last component — documents the
        // behaviour so a ".tar.gz" becomes "x tar 2.gz" (acceptable; matches
        // the rest of the codebase's URL-based naming).
        XCTAssertEqual(RenamePlan.uniqueName(for: "x.md", exists: empty), "x 2.md")
        XCTAssertEqual(RenamePlan.uniqueName(for: "noext", exists: empty), "noext 2")
    }
}
