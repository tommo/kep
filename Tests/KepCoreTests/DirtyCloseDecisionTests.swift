import XCTest
@testable import KepCore

final class DirtyCloseDecisionTests: XCTestCase {
    private func items(_ pairs: [(Int, Bool)]) -> [DirtyCloseDecision.Item<Int>] {
        pairs.map { DirtyCloseDecision.Item(id: $0.0, isDirty: $0.1) }
    }

    func testNoDirtyNeedsNoPrompt() {
        let set = items([(1, false), (2, false)])
        XCTAssertFalse(DirtyCloseDecision.needsPrompt(among: set))
        XCTAssertTrue(DirtyCloseDecision.dirtyIDs(among: set).isEmpty)
    }

    func testSingleDirtyNeedsPrompt() {
        let set = items([(1, false), (2, true)])
        XCTAssertTrue(DirtyCloseDecision.needsPrompt(among: set))
        XCTAssertEqual(DirtyCloseDecision.dirtyIDs(among: set), [2])
    }

    func testDirtyOrderPreserved() {
        // The batch prompt lists titles in this order, so it must be stable.
        let set = items([(3, true), (1, false), (2, true), (4, true)])
        XCTAssertEqual(DirtyCloseDecision.dirtyIDs(among: set), [3, 2, 4])
    }

    func testEmptySetNeedsNoPrompt() {
        XCTAssertFalse(DirtyCloseDecision.needsPrompt(among: items([])))
    }
}
