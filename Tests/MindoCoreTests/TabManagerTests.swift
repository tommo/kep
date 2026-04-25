import XCTest
import MindoBase

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

    func testCycleNoOpsWithFewerThanTwo() {
        let mgr = TabManager<Int>()
        XCTAssertNil(mgr.nextMRU(after: 1))
        mgr.activate(1)
        XCTAssertNil(mgr.nextMRU(after: 1))
    }
}

@MainActor
final class EditorContextTests: XCTestCase {

    func testMarkDirtyAndSavedRoundTrip() {
        let ctx = EditorContext(fileURL: nil, title: "Untitled.md", fileType: .markdown)
        XCTAssertFalse(ctx.isDirty)
        ctx.markDirty()
        XCTAssertTrue(ctx.isDirty)
        ctx.markSaved()
        XCTAssertFalse(ctx.isDirty)
        XCTAssertNotNil(ctx.lastSavedAt)
    }

    func testHasOnDiskBackingFollowsURL() {
        let ctx = EditorContext(fileURL: nil, title: "tmp")
        XCTAssertFalse(ctx.hasOnDiskBacking)
        ctx.fileURL = URL(fileURLWithPath: "/tmp/x.md")
        XCTAssertTrue(ctx.hasOnDiskBacking)
    }
}
