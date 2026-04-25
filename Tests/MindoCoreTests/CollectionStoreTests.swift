import XCTest
@testable import MindoCore

final class CollectionStoreTests: XCTestCase {

    private func makeStore() throws -> (CollectionStore, URL) {
        let tmp = try makeScratchDirectory(prefix: "mindo-coll")
        return (CollectionStore(directory: tmp, recentLimit: 5), tmp)
    }

    func testAddCollectionPersistsAndDedupesByName() throws {
        let (store, dir) = try makeStore()
        _ = store.addCollection(name: "Project A", fileURLs: [URL(fileURLWithPath: "/a.mmd")])
        _ = store.addCollection(name: "Project A", fileURLs: [URL(fileURLWithPath: "/b.mmd")])
        XCTAssertEqual(store.collections.count, 1, "second add with same name replaces")
        XCTAssertEqual(store.collections.first?.filePaths, ["/b.mmd"])

        let store2 = CollectionStore(directory: dir, recentLimit: 5)
        XCTAssertEqual(store2.collections.first?.name, "Project A")
        XCTAssertEqual(store2.collections.first?.filePaths, ["/b.mmd"])
    }

    func testRemoveAndRename() throws {
        let (store, _) = try makeStore()
        let coll = store.addCollection(name: "Notes", fileURLs: [URL(fileURLWithPath: "/n.md")])
        store.rename(collectionID: coll.id, to: "My Notes")
        XCTAssertEqual(store.collections.first?.name, "My Notes")
        store.remove(collectionID: coll.id)
        XCTAssertTrue(store.collections.isEmpty)
    }

    func testTouchPromotesAndCapsRecents() throws {
        let (store, _) = try makeStore()  // recentLimit = 5
        for i in 0..<7 {
            store.touch(url: URL(fileURLWithPath: "/file-\(i).mmd"))
        }
        XCTAssertEqual(store.recents.count, 5)
        XCTAssertEqual(store.recents.first?.path, "/file-6.mmd", "most recent first")
        XCTAssertFalse(store.recents.contains { $0.path == "/file-0.mmd" }, "oldest fell off")
    }

    func testTouchOnExistingPromotesItToFront() throws {
        let (store, _) = try makeStore()
        store.touch(url: URL(fileURLWithPath: "/a"))
        store.touch(url: URL(fileURLWithPath: "/b"))
        store.touch(url: URL(fileURLWithPath: "/a"))
        XCTAssertEqual(store.recents.map(\.path), ["/a", "/b"])
    }

    func testRecentsPersistAcrossInstances() throws {
        let (store, dir) = try makeStore()
        store.touch(url: URL(fileURLWithPath: "/persisted.md"))
        let store2 = CollectionStore(directory: dir, recentLimit: 5)
        XCTAssertEqual(store2.recents.first?.path, "/persisted.md")
    }
}
