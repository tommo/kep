import XCTest
@testable import KepCore

final class WorkspaceTests: XCTestCase {

    // MARK: - WorkspaceMeta / WorkspaceList

    func testWorkspaceMetaContainsNestedFile() {
        let meta = WorkspaceMeta(baseDirPath: "/Users/me/proj")
        XCTAssertTrue(meta.contains(URL(fileURLWithPath: "/Users/me/proj/notes/file.mmd")))
        XCTAssertTrue(meta.contains(URL(fileURLWithPath: "/Users/me/proj")))
        XCTAssertFalse(meta.contains(URL(fileURLWithPath: "/Users/me/proj-other/x.txt")))
    }

    func testWorkspaceListMatchesDeepest() {
        var list = WorkspaceList(projects: [
            WorkspaceMeta(baseDirPath: "/a"),
            WorkspaceMeta(baseDirPath: "/a/b"),
            WorkspaceMeta(baseDirPath: "/c"),
        ])
        XCTAssertEqual(list.match(filePath: "/a/b/file.mmd")?.baseDirPath, "/a/b")
        XCTAssertEqual(list.match(filePath: "/a/file.mmd")?.baseDirPath, "/a")
        XCTAssertNil(list.match(filePath: "/zzz/file.mmd"))

        // Adding the same workspace twice is idempotent.
        list.add(WorkspaceMeta(baseDirPath: "/a"))
        XCTAssertEqual(list.projects.count, 3)
    }

    func testWorkspaceListJSONRoundTrip() throws {
        let list = WorkspaceList(projects: [
            WorkspaceMeta(baseDirPath: "/Users/me/proj"),
            WorkspaceMeta(baseDirPath: "/Users/me/notes"),
        ])
        let data = try JSONEncoder().encode(list)
        let decoded = try JSONDecoder().decode(WorkspaceList.self, from: data)
        XCTAssertEqual(decoded.projects.count, 2)
        XCTAssertEqual(decoded.projects.first?.baseDirPath, "/Users/me/proj")
    }

    // MARK: - WorkspaceConfig filtering

    func testWorkspaceConfigSuffixFilter() {
        let cfg = WorkspaceConfig(includeSuffixes: [".mmd", ".md"])
        XCTAssertTrue(cfg.acceptsFile(URL(fileURLWithPath: "/x/y.mmd")))
        XCTAssertTrue(cfg.acceptsFile(URL(fileURLWithPath: "/x/y.MD")))
        XCTAssertFalse(cfg.acceptsFile(URL(fileURLWithPath: "/x/y.png")))
        XCTAssertFalse(cfg.acceptsFile(URL(fileURLWithPath: "/x/.DS_Store")))
    }

    func testWorkspaceConfigHidesDotFiles() {
        let cfg = WorkspaceConfig.default
        XCTAssertFalse(cfg.acceptsFile(URL(fileURLWithPath: "/x/.hidden")))
        XCTAssertFalse(cfg.acceptsDirectory(URL(fileURLWithPath: "/x/.git")))
        XCTAssertTrue(cfg.acceptsDirectory(URL(fileURLWithPath: "/x/source")))
    }

    // MARK: - NodeData enumeration

    /// Build a small directory tree under a temp folder, then assert that NodeData
    /// enumerates folders before files in localized order.
    func testNodeDataEnumeratesFoldersBeforeFiles() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("kep-ws-\(UUID())")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        // Create a small layout: zfolder/, anotes/, b.mmd, a.txt, .hidden
        try fm.createDirectory(at: tmp.appendingPathComponent("zfolder"), withIntermediateDirectories: true)
        try fm.createDirectory(at: tmp.appendingPathComponent("anotes"), withIntermediateDirectories: true)
        try "x".write(to: tmp.appendingPathComponent("b.mmd"), atomically: true, encoding: .utf8)
        try "y".write(to: tmp.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "z".write(to: tmp.appendingPathComponent(".hidden"), atomically: true, encoding: .utf8)

        let workspace = NodeData(workspace: tmp.lastPathComponent, url: tmp)
        workspace.workspace = workspace
        let kids = workspace.children()
        XCTAssertEqual(kids.map(\.name), ["anotes", "zfolder", "a.txt", "b.mmd"])
        XCTAssertTrue(kids[0].isFolder)
        XCTAssertTrue(kids[2].isFile)
        XCTAssertEqual(kids[3].fileType, .mindMap)
    }

    // MARK: - SupportedFileType

    func testSupportedFileTypeClassification() {
        XCTAssertEqual(SupportedFileType.classify(name: "x.mmd"), .mindMap)
        XCTAssertEqual(SupportedFileType.classify(name: "X.MMD"), .mindMap)
        XCTAssertEqual(SupportedFileType.classify(name: "doc.MD"), .markdown)
        XCTAssertEqual(SupportedFileType.classify(name: "diagram.puml"), .plantUML)
        XCTAssertNil(SupportedFileType.classify(name: "binary.exe"))
    }

    func testSupportedFileTypeSFSymbolNames() {
        // Every case must produce a non-empty symbol name so DocumentTabBar /
        // SidebarView NodeRow never end up rendering an empty Image.
        for type in SupportedFileType.allCases {
            XCTAssertFalse(type.sfSymbolName.isEmpty, "missing symbol for \(type)")
        }
        // Spot-check that the dedicated symbols stayed mapped through the
        // SupportedFileType.sfSymbolName extraction so the tabs/sidebar don't
        // silently revert to a generic doc icon.
        XCTAssertEqual(SupportedFileType.mindMap.sfSymbolName, "brain")
        XCTAssertEqual(SupportedFileType.markdown.sfSymbolName, "text.alignleft")
        XCTAssertEqual(SupportedFileType.jpeg.sfSymbolName, "photo")
        XCTAssertEqual(SupportedFileType.png.sfSymbolName, "photo")
        XCTAssertFalse(SupportedFileType.unknownSymbolName.isEmpty)
    }

    // MARK: - WorkspaceManager

    func testWorkspaceManagerPersistsAndReloads() throws {
        let tmp = try makeScratchDirectory(prefix: "kep-mgr")
        defer { try? FileManager.default.removeItem(at: tmp) }

        let mgr = WorkspaceManager(directory: tmp)
        let proj = tmp.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        _ = mgr.add(workspaceAt: proj)
        try mgr.save()

        let mgr2 = WorkspaceManager(directory: tmp)
        XCTAssertEqual(mgr2.list.projects.first?.baseDirPath, proj.path)
    }

    // MARK: - WorkspaceConfig.fromPreferences

    func testConfigFromPreferencesReadsToggleOn() {
        // Round-trip: flip the pref ON, build a fresh config, verify
        // both file + dir flags follow. Restores prior state.
        let key = PrefKeys.showHiddenFiles
        let prior = UserDefaults.standard.object(forKey: key)
        defer {
            if let prior { UserDefaults.standard.set(prior, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set(true, forKey: key)
        let cfg = WorkspaceConfig.fromPreferences()
        XCTAssertTrue(cfg.showHiddenFiles)
        XCTAssertTrue(cfg.showHiddenDirectories)
    }
}
