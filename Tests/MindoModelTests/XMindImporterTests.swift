import XCTest
@testable import MindoModel

final class XMindImporterTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("XMindTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        if let dir, FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    /// Zip a content.json (+ optional siblings) into a .xmind and return its bytes.
    private func makeXMind(contentJSON: String, extraFiles: [String: String] = [:]) throws -> Data {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "no /usr/bin/zip")
        try contentJSON.write(to: dir.appendingPathComponent("content.json"), atomically: true, encoding: .utf8)
        var args = ["-q", "doc.xmind", "content.json"]
        for (name, body) in extraFiles {
            try body.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
            args.append(name)
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        try XCTSkipUnless(p.terminationStatus == 0, "zip failed")
        return try Data(contentsOf: dir.appendingPathComponent("doc.xmind"))
    }

    func testImportsZenTreeWithNotes() throws {
        let json = """
        [{
          "title": "Sheet 1",
          "rootTopic": {
            "title": "Central",
            "notes": { "plain": { "content": "root note" } },
            "children": { "attached": [
              { "title": "Main 1", "children": { "attached": [
                 { "title": "Sub 1.1" }, { "title": "Sub 1.2" } ] } },
              { "title": "Main 2", "notes": { "plain": { "content": "m2 note" } } }
            ] }
          }
        }]
        """
        let data = try makeXMind(contentJSON: json)
        let map = try XMindImporter.parse(data: data)

        XCTAssertEqual(map.root?.text, "Central")
        XCTAssertEqual((map.root?.extra(.note) as? ExtraNote)?.text, "root note")
        XCTAssertEqual(map.root?.children.map(\.text), ["Main 1", "Main 2"])
        XCTAssertEqual(map.root?.children.first?.children.map(\.text), ["Sub 1.1", "Sub 1.2"])
        XCTAssertEqual((map.root?.children.last?.extra(.note) as? ExtraNote)?.text, "m2 note")
    }

    func testEmptyTitleFallsBackToCentral() throws {
        let data = try makeXMind(contentJSON: #"[{"rootTopic":{"title":"   "}}]"#)
        XCTAssertEqual(try XMindImporter.parse(data: data).root?.text, "Central Topic")
    }

    func testLegacyXmlSurfacesClearError() throws {
        // A bundle with content.xml but no content.json → legacy, unsupported.
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: "/usr/bin/zip"), "no /usr/bin/zip")
        try "<xml/>".write(to: dir.appendingPathComponent("content.xml"), atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-q", "legacy.xmind", "content.xml"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        let data = try Data(contentsOf: dir.appendingPathComponent("legacy.xmind"))
        XCTAssertThrowsError(try XMindImporter.parse(data: data)) { error in
            XCTAssertEqual(error as? XMindImporter.ImportError, .legacyUnsupported)
        }
    }

    func testNonZipThrows() {
        XCTAssertThrowsError(try XMindImporter.parse(data: Data("nope".utf8))) { error in
            XCTAssertEqual(error as? XMindImporter.ImportError, .notAZip)
        }
    }
}

extension XMindImporter.ImportError: Equatable {
    public static func == (l: Self, r: Self) -> Bool { l.localizedDescription == r.localizedDescription }
}
