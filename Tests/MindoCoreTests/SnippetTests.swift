import XCTest
import MindoCore
@testable import MindoBase

@MainActor
final class SnippetStoreTests: XCTestCase {

    private func makeStore() throws -> (SnippetStore, URL) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("mindo-snip-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return (SnippetStore(directory: tmp), tmp)
    }

    func testBuiltInSeedsCoverEachEditorType() throws {
        let (store, _) = try makeStore()
        XCTAssertTrue(store.builtIn.contains { $0.fileType == .markdown })
        XCTAssertTrue(store.builtIn.contains { $0.fileType == .plantUML })
        XCTAssertTrue(store.builtIn.contains { $0.fileType == .mindMap })
    }

    func testFilterByFileTypeRespectsAnySnippets() throws {
        let (store, _) = try makeStore()
        let mdOnly = store.filter(fileType: .markdown, query: "")
        XCTAssertFalse(mdOnly.isEmpty)
        for s in mdOnly {
            XCTAssertTrue(s.fileType == nil || s.fileType == .markdown)
        }
        // PlantUML-typed snippets should not appear when filtering for Markdown.
        let pumlSnippet = store.builtIn.first(where: { $0.fileType == .plantUML })!
        XCTAssertFalse(mdOnly.contains(pumlSnippet))
    }

    func testQueryMatchesTitleBodyAndTags() throws {
        let (store, _) = try makeStore()
        XCTAssertFalse(store.filter(fileType: nil, query: "table").isEmpty)
        XCTAssertFalse(store.filter(fileType: nil, query: "actor").isEmpty)   // body match
        XCTAssertTrue(store.filter(fileType: nil, query: "definitely-not-here").isEmpty)
    }

    func testAddRemoveAndPersist() throws {
        let (store, dir) = try makeStore()
        let snippet = Snippet(title: "My snippet", body: "hello", fileType: .markdown, tags: ["custom"])
        store.add(snippet)
        XCTAssertTrue(store.userSnippets.contains { $0.title == "My snippet" })

        // Reloading from the same directory should pick the user snippet up.
        let store2 = SnippetStore(directory: dir)
        XCTAssertTrue(store2.userSnippets.contains { $0.title == "My snippet" })

        store2.remove(id: snippet.id)
        XCTAssertFalse(store2.userSnippets.contains { $0.id == snippet.id })

        let store3 = SnippetStore(directory: dir)
        XCTAssertFalse(store3.userSnippets.contains { $0.id == snippet.id })
    }

    func testIsBuiltInForcedFalseOnAdd() throws {
        let (store, _) = try makeStore()
        let snippet = Snippet(title: "x", body: "y", isBuiltIn: true)
        store.add(snippet)
        let stored = store.userSnippets.first { $0.title == "x" }
        XCTAssertNotNil(stored)
        XCTAssertFalse(stored!.isBuiltIn)
    }
}
