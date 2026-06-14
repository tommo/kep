import XCTest
@testable import MindoCore

final class WorkspaceFileIndexTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wfindex-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func touch(_ relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "x".write(to: url, atomically: true, encoding: .utf8)
    }

    func testIndexesNestedFiles() throws {
        try touch("a.md")
        try touch("sub/b.mmd")
        try touch("sub/deep/c.csv")
        let files = WorkspaceFileIndex.index(
            roots: [(root, "WS")], config: .default)
        XCTAssertEqual(Set(files.map(\.name)), ["a.md", "b.mmd", "c.csv"])
    }

    func testRelativePathIsWorkspaceRelative() throws {
        try touch("sub/deep/c.csv")
        let files = WorkspaceFileIndex.index(roots: [(root, "WS")], config: .default)
        XCTAssertEqual(files.first?.relativePath, "sub/deep/c.csv")
        XCTAssertEqual(files.first?.workspaceName, "WS")
    }

    func testHiddenFilesExcludedByDefault() throws {
        try touch("visible.md")
        try touch(".hidden.md")
        let files = WorkspaceFileIndex.index(
            roots: [(root, "WS")],
            config: WorkspaceConfig(showHiddenFiles: false, showHiddenDirectories: false))
        XCTAssertEqual(files.map(\.name), ["visible.md"])
    }

    func testHiddenDirectoriesSkipped() throws {
        try touch(".git/config")
        try touch("keep.md")
        let files = WorkspaceFileIndex.index(
            roots: [(root, "WS")],
            config: WorkspaceConfig(showHiddenFiles: false, showHiddenDirectories: false))
        XCTAssertEqual(files.map(\.name), ["keep.md"])
    }

    func testExcludeSuffixDropsDSStore() throws {
        try touch(".DS_Store")
        try touch("real.md")
        // showHidden so the dotfile would otherwise pass; excludeSuffixes still drops it.
        let files = WorkspaceFileIndex.index(
            roots: [(root, "WS")],
            config: WorkspaceConfig(excludeSuffixes: [".DS_Store"], showHiddenFiles: true))
        XCTAssertEqual(files.map(\.name), ["real.md"])
    }

    func testDeterministicFolderThenFileOrdering() throws {
        try touch("zzz.md")          // file at root
        try touch("aaa/inner.md")    // folder at root
        let files = WorkspaceFileIndex.index(roots: [(root, "WS")], config: .default)
        // Files in a directory come before recursing into subfolders.
        XCTAssertEqual(files.map(\.name), ["zzz.md", "inner.md"])
    }

    func testMaxFilesCapStopsEarly() throws {
        for i in 0..<10 { try touch("f\(i).md") }
        let files = WorkspaceFileIndex.index(roots: [(root, "WS")], config: .default, maxFiles: 4)
        XCTAssertEqual(files.count, 4)
    }

    func testEmptyWorkspaceYieldsNothing() {
        let files = WorkspaceFileIndex.index(roots: [(root, "WS")], config: .default)
        XCTAssertTrue(files.isEmpty)
    }
}
