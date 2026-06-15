import XCTest
@testable import MindoCore

/// NodeData identity must be by URL, not object identity. The sidebar rebuilds
/// child instances on every workspace reload (FSEvents burst when a file is
/// opened); if equality were instance-based, the List selection would point at
/// a stale object and silently clear — the "select mmd → graph shows → tree row
/// deselects" bug.
final class NodeDataIdentityTests: XCTestCase {

    private func makeWorkspace() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("nodedata-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data().write(to: dir.appendingPathComponent("map.mmd"))
        try Data().write(to: dir.appendingPathComponent("notes.md"))
        return dir
    }

    func testSameURLNodesAreEqual() {
        let url = URL(fileURLWithPath: "/tmp/ws/map.mmd")
        let a = NodeData(nodeType: .file, url: url)
        let b = NodeData(nodeType: .file, url: url)
        XCTAssertEqual(a, b, "two instances naming the same path are equal")
        XCTAssertEqual(a.hashValue, b.hashValue, "and hash the same")
    }

    func testDifferentURLNodesAreNotEqual() {
        let a = NodeData(nodeType: .file, url: URL(fileURLWithPath: "/tmp/ws/a.mmd"))
        let b = NodeData(nodeType: .file, url: URL(fileURLWithPath: "/tmp/ws/b.mmd"))
        XCTAssertNotEqual(a, b)
    }

    /// The actual regression: a selected child must still match a row after the
    /// workspace reloads and rebuilds its children with fresh instances.
    func testSelectionSurvivesReload() throws {
        let dir = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: dir) }

        let root = NodeData(workspace: "ws", url: dir)
        let firstPass = root.children()
        let selected = try XCTUnwrap(firstPass.first { $0.url.lastPathComponent == "map.mmd" })

        // FSEvents burst → reload rebuilds child NodeData instances.
        root.reloadChildren()
        let secondPass = root.children()

        // Brand-new objects...
        XCTAssertFalse(secondPass.contains { $0 === selected },
                       "reload really does create fresh instances")
        // ...but the selection still resolves by URL identity.
        XCTAssertTrue(secondPass.contains(selected),
                      "a List selection holding the old instance still matches a reloaded row")
    }
}
