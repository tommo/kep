import XCTest
import KepBase

final class TabManagerTests: XCTestCase {

    func testActivateMovesToFront() {
        let mgr = TabManager<Int>()
        mgr.activate(1)
        mgr.activate(2)
        mgr.activate(3)
        XCTAssertEqual(mgr.ids, [3, 2, 1])
        XCTAssertEqual(mgr.activeID, 3)
        XCTAssertEqual(mgr.previousID, 2)
    }

    func testReactivatingPromotesToFront() {
        let mgr = TabManager<Int>()
        for id in [1, 2, 3] { mgr.activate(id) }
        mgr.activate(1)
        XCTAssertEqual(mgr.ids, [1, 3, 2])
    }

    func testNextAndPreviousCycle() {
        let mgr = TabManager<Int>()
        for id in [1, 2, 3] { mgr.activate(id) }   // order: [3,2,1]
        XCTAssertEqual(mgr.nextMRU(after: 3), 2)
        XCTAssertEqual(mgr.nextMRU(after: 2), 1)
        XCTAssertEqual(mgr.nextMRU(after: 1), 3)   // wraps
        XCTAssertEqual(mgr.previousMRU(before: 3), 1) // wraps backwards
    }

    func testRemoveDropsEntry() {
        let mgr = TabManager<Int>()
        for id in [1, 2, 3] { mgr.activate(id) }
        mgr.remove(2)
        XCTAssertEqual(mgr.ids, [3, 1])
        XCTAssertNil(mgr.mruIndex(of: 2))
    }

    /// Regression for the tab-close bug: closing the *active* tab must
    /// drop it from the MRU so `activeID` advances to the next tab rather
    /// than dangling on the closed one (the old inline close path skipped
    /// `remove`, leaving ⌃⇥ pointing at a dead tab).
    func testRemoveActivePromotesNextMRU() {
        let mgr = TabManager<Int>()
        for id in [1, 2, 3] { mgr.activate(id) }   // MRU front = 3 (active)
        XCTAssertEqual(mgr.activeID, 3)
        mgr.remove(3)
        XCTAssertEqual(mgr.activeID, 2)            // not the removed 3
        XCTAssertNil(mgr.mruIndex(of: 3))
    }

    func testCycleNoOpsWithFewerThanTwo() {
        let mgr = TabManager<Int>()
        XCTAssertNil(mgr.nextMRU(after: 1))
        mgr.activate(1)
        XCTAssertNil(mgr.nextMRU(after: 1))
    }
}
