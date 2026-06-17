import XCTest
@testable import MindoCore

final class SidebarSortTests: XCTestCase {

    private func node(_ name: String, _ type: NodeType) -> NodeData {
        NodeData(nodeType: type, url: URL(fileURLWithPath: "/ws/\(name)"))
    }

    private func sampleNodes() -> [NodeData] {
        [node("zfolder", .folder), node("b.md", .file), node("afolder", .folder),
         node("a.md", .file), node("c.md", .file)]
    }

    func testNameSortFoldersFirstThenAlpha() {
        let r = SidebarSort.sorted(sampleNodes(), mode: .name)
        XCTAssertEqual(r.map(\.name), ["afolder", "zfolder", "a.md", "b.md", "c.md"])
    }

    func testRecentSortOrdersFilesByRecency() {
        let recents = [URL(fileURLWithPath: "/ws/c.md"), URL(fileURLWithPath: "/ws/a.md")]
        let r = SidebarSort.sorted(sampleNodes(), mode: .recent, recents: recents)
        // Folders still first; files: c, a (recents order), then b (not recent → alpha tail).
        XCTAssertEqual(r.map(\.name), ["afolder", "zfolder", "c.md", "a.md", "b.md"])
    }

    func testModifiedSortNewestFirst() {
        let dates: [String: Date] = [
            "/ws/a.md": Date(timeIntervalSince1970: 100),
            "/ws/b.md": Date(timeIntervalSince1970: 300),
            "/ws/c.md": Date(timeIntervalSince1970: 200),
        ]
        let r = SidebarSort.sorted(sampleNodes(), mode: .modified,
                                   modifiedAt: { dates[$0.path] ?? .distantPast })
        XCTAssertEqual(r.map(\.name), ["afolder", "zfolder", "b.md", "c.md", "a.md"])
    }
}
