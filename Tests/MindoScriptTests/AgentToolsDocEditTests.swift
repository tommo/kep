import XCTest
import Foundation
import MindoModel
@testable import MindoScript

final class AgentToolsDocEditTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocEditTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
    }

    // MARK: - Helpers

    /// Build a tools instance rooted at the temp dir, seeding allFiles with the
    /// given existing file URLs.
    private func makeTools(files: [URL] = []) -> (MindoAgentTools, AgentToolEffects) {
        let map = MindMap(root: Topic(text: "Root"))
        let effects = AgentToolEffects()
        let corpus = files.compactMap { url -> (url: URL, text: String)? in
            guard let t = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url, t)
        }
        let tools = MindoAgentTools(map: map, corpus: corpus, allFiles: files,
                                    workspaceRoot: tempDir, effects: effects)
        return (tools, effects)
    }

    @discardableResult
    private func writeFile(_ name: String, _ content: String) throws -> URL {
        let url = tempDir.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOf: tempDir.appendingPathComponent(name), encoding: .utf8)
    }

    private func json(_ dict: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: dict), encoding: .utf8)!
    }

    // MARK: - Same-run sequential edits (regression: stale-snapshot data loss)

    /// create then append within ONE tools instance must preserve the created
    /// body (the start-of-run allFiles/corpus snapshot can't see the new file).
    func testCreateThenAppendSameRunPreservesContent() throws {
        let (tools, _) = makeTools()
        XCTAssertTrue(tools.handle(name: "create_document",
                                   argumentsJSON: json(["name": "plan", "content": "A\nB\nC"])).hasPrefix("created"))
        let r = tools.handle(name: "append_to_document",
                             argumentsJSON: json(["name": "plan", "content": "D"]))
        XCTAssertFalse(r.hasPrefix("error"), r)
        XCTAssertEqual(try read("plan.md"), "A\nB\nC\nD", "append must build on the same-run create, not clobber it")
    }

    /// A second create of the same name in one run must be refused (the dup
    /// guard has to see the same-run creation), not silently clobber.
    func testSecondCreateSameRunRefused() throws {
        let (tools, _) = makeTools()
        _ = tools.handle(name: "create_document", argumentsJSON: json(["name": "plan", "content": "first"]))
        let r = tools.handle(name: "create_document", argumentsJSON: json(["name": "plan", "content": "second"]))
        XCTAssertTrue(r.contains("already exists"), r)
        XCTAssertEqual(try read("plan.md"), "first")
    }

    /// overwrite then read within one run sees the freshest bytes via the live
    /// overlay, not the stale snapshot.
    func testOverwriteThenReadSameRun() throws {
        let existing = try writeFile("doc.md", "old")
        let (tools, _) = makeTools(files: [existing])
        _ = tools.handle(name: "overwrite_document", argumentsJSON: json(["name": "doc", "content": "new"]))
        XCTAssertEqual(tools.handle(name: "read_document", argumentsJSON: json(["name": "doc"])), "new")
    }

    // MARK: - Ambiguity guard (regression: silent wrong-file clobber)

    func testAmbiguousBareNameRefused() throws {
        let a = try writeFile("report.md", "MD")
        // a same-base file in a different (nested) location
        let sub = tempDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        let b = sub.appendingPathComponent("report.txt")
        try "TXT".write(to: b, atomically: true, encoding: .utf8)
        let (tools, _) = makeTools(files: [a, b])
        let r = tools.handle(name: "overwrite_document", argumentsJSON: json(["name": "report", "content": "X"]))
        XCTAssertTrue(r.hasPrefix("error:") && r.contains("ambiguous"), r)
        // Neither file was touched.
        XCTAssertEqual(try read("report.md"), "MD")
        XCTAssertEqual(try String(contentsOf: b, encoding: .utf8), "TXT")
        // Passing the full filename disambiguates.
        let ok = tools.handle(name: "overwrite_document", argumentsJSON: json(["name": "report.md", "content": "X"]))
        XCTAssertFalse(ok.hasPrefix("error:"), ok)
        XCTAssertEqual(try read("report.md"), "X")
    }

    func testExtensionNotDoubled() throws {
        let (tools, _) = makeTools()
        _ = tools.handle(name: "create_document",
                         argumentsJSON: json(["name": "data.csv", "type": "md", "content": "x"]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("data.csv").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("data.csv.md").path))
    }

    // MARK: - create_document

    func testCreateDocumentHappyPath() throws {
        let (tools, effects) = makeTools()
        let result = tools.handle(name: "create_document",
                                  argumentsJSON: json(["name": "Notes", "content": "Hello"]))
        XCTAssertTrue(result.hasPrefix("created"), result)
        XCTAssertEqual(try read("Notes.md"), "Hello")
        let url = tempDir.appendingPathComponent("Notes.md")
        XCTAssertTrue(effects.createdFiles.contains(url))
        XCTAssertTrue(effects.changedFiles.contains(url))
    }

    func testCreateDocumentDefaultsEmptyContent() throws {
        let (tools, _) = makeTools()
        let result = tools.handle(name: "create_document", argumentsJSON: json(["name": "Empty"]))
        XCTAssertTrue(result.hasPrefix("created"), result)
        XCTAssertEqual(try read("Empty.md"), "")
    }

    func testCreateDocumentRespectsType() throws {
        let (tools, _) = makeTools()
        let result = tools.handle(name: "create_document",
                                  argumentsJSON: json(["name": "Diagram", "type": "puml", "content": "@startuml"]))
        XCTAssertTrue(result.hasPrefix("created"), result)
        XCTAssertEqual(try read("Diagram.puml"), "@startuml")
    }

    func testCreateDocumentMissingName() {
        let (tools, _) = makeTools()
        XCTAssertEqual(tools.handle(name: "create_document", argumentsJSON: json([:])),
                       "error: missing 'name'")
    }

    func testCreateDocumentAlreadyExists() throws {
        let existing = try writeFile("Existing.md", "old")
        let (tools, _) = makeTools(files: [existing])
        let result = tools.handle(name: "create_document",
                                  argumentsJSON: json(["name": "Existing", "content": "new"]))
        XCTAssertEqual(result, "error: Existing already exists (use overwrite_document)")
        XCTAssertEqual(try read("Existing.md"), "old")
    }

    func testCreateDocumentNoWorkspace() {
        let map = MindMap(root: Topic(text: "Root"))
        let tools = MindoAgentTools(map: map, workspaceRoot: nil)
        let result = tools.handle(name: "create_document", argumentsJSON: json(["name": "X"]))
        XCTAssertEqual(result, "error: no workspace folder to create in")
    }

    // MARK: - overwrite_document

    func testOverwriteExisting() throws {
        let existing = try writeFile("Doc.md", "old body")
        let (tools, effects) = makeTools(files: [existing])
        let result = tools.handle(name: "overwrite_document",
                                  argumentsJSON: json(["name": "Doc", "content": "fresh"]))
        XCTAssertTrue(result.hasPrefix("wrote"), result)
        XCTAssertEqual(try read("Doc.md"), "fresh")
        XCTAssertFalse(effects.createdFiles.contains(existing))
        XCTAssertTrue(effects.changedFiles.contains(existing))
    }

    func testOverwriteCreatesWhenMissing() throws {
        let (tools, effects) = makeTools()
        let result = tools.handle(name: "overwrite_document",
                                  argumentsJSON: json(["name": "Brand", "content": "body"]))
        XCTAssertTrue(result.hasPrefix("created"), result)
        XCTAssertEqual(try read("Brand.md"), "body")
        XCTAssertTrue(effects.createdFiles.contains(tempDir.appendingPathComponent("Brand.md")))
    }

    func testOverwriteMissingContent() {
        let (tools, _) = makeTools()
        XCTAssertEqual(tools.handle(name: "overwrite_document", argumentsJSON: json(["name": "Doc"])),
                       "error: missing 'content'")
    }

    func testOverwriteMissingName() {
        let (tools, _) = makeTools()
        XCTAssertEqual(tools.handle(name: "overwrite_document", argumentsJSON: json(["content": "x"])),
                       "error: missing 'name'")
    }

    // MARK: - append_to_document

    func testAppendToExistingNonEmpty() throws {
        let existing = try writeFile("Log.md", "line one")
        let (tools, _) = makeTools(files: [existing])
        let result = tools.handle(name: "append_to_document",
                                  argumentsJSON: json(["name": "Log", "content": "line two"]))
        XCTAssertTrue(result.hasPrefix("wrote"), result)
        XCTAssertEqual(try read("Log.md"), "line one\nline two")
    }

    func testAppendToExistingEmpty() throws {
        let existing = try writeFile("Empty.md", "")
        let (tools, _) = makeTools(files: [existing])
        let result = tools.handle(name: "append_to_document",
                                  argumentsJSON: json(["name": "Empty", "content": "first"]))
        XCTAssertTrue(result.hasPrefix("wrote"), result)
        XCTAssertEqual(try read("Empty.md"), "first")
    }

    func testAppendCreatesWhenMissing() throws {
        let (tools, effects) = makeTools()
        let result = tools.handle(name: "append_to_document",
                                  argumentsJSON: json(["name": "New", "content": "hello"]))
        XCTAssertTrue(result.hasPrefix("created"), result)
        XCTAssertEqual(try read("New.md"), "hello")
        XCTAssertTrue(effects.createdFiles.contains(tempDir.appendingPathComponent("New.md")))
    }

    func testAppendMissingContent() {
        let (tools, _) = makeTools()
        XCTAssertEqual(tools.handle(name: "append_to_document", argumentsJSON: json(["name": "Log"])),
                       "error: missing 'content'")
    }

    // MARK: - replace_section

    func testReplaceSectionMiddle() throws {
        let body = "# Title\n\n## A\nold a body\n\n## B\nb body\n"
        let existing = try writeFile("Sec.md", body)
        let (tools, _) = makeTools(files: [existing])
        let result = tools.handle(name: "replace_section",
                                  argumentsJSON: json(["name": "Sec", "heading": "A", "content": "new a body"]))
        XCTAssertTrue(result.hasPrefix("wrote"), result)
        let out = try read("Sec.md")
        XCTAssertEqual(out, "# Title\n\n## A\nnew a body\n## B\nb body\n")
    }

    func testReplaceSectionLastToEnd() throws {
        let body = "# Title\n## A\na body\n## B\nold b\nmore b\n"
        let existing = try writeFile("Sec.md", body)
        let (tools, _) = makeTools(files: [existing])
        _ = tools.handle(name: "replace_section",
                         argumentsJSON: json(["name": "Sec", "heading": "B", "content": "new b"]))
        let out = try read("Sec.md")
        XCTAssertEqual(out, "# Title\n## A\na body\n## B\nnew b")
    }

    func testReplaceSectionCaseInsensitive() throws {
        let body = "## Heading One\nbody\n## Two\nx\n"
        let existing = try writeFile("Sec.md", body)
        let (tools, _) = makeTools(files: [existing])
        let result = tools.handle(name: "replace_section",
                                  argumentsJSON: json(["name": "Sec", "heading": "heading one", "content": "Z"]))
        XCTAssertTrue(result.hasPrefix("wrote"), result)
        XCTAssertEqual(try read("Sec.md"), "## Heading One\nZ\n## Two\nx\n")
    }

    func testReplaceSectionStopsAtHigherLevel() throws {
        let body = "## A\nbody a\n# Top\ntop body\n"
        let existing = try writeFile("Sec.md", body)
        let (tools, _) = makeTools(files: [existing])
        _ = tools.handle(name: "replace_section",
                         argumentsJSON: json(["name": "Sec", "heading": "A", "content": "replaced"]))
        XCTAssertEqual(try read("Sec.md"), "## A\nreplaced\n# Top\ntop body\n")
    }

    func testReplaceSectionHeadingNotFound() throws {
        let existing = try writeFile("Sec.md", "## A\nbody\n")
        let (tools, _) = makeTools(files: [existing])
        XCTAssertEqual(tools.handle(name: "replace_section",
                                    argumentsJSON: json(["name": "Sec", "heading": "Nope", "content": "x"])),
                       "error: heading not found")
    }

    func testReplaceSectionDocNotFound() {
        let (tools, _) = makeTools()
        XCTAssertEqual(tools.handle(name: "replace_section",
                                    argumentsJSON: json(["name": "Ghost", "heading": "A", "content": "x"])),
                       "error: Ghost not found")
    }

    // MARK: - insert_after_heading

    func testInsertAfterHeading() throws {
        let body = "# Title\nintro\n## A\nold a\n"
        let existing = try writeFile("Ins.md", body)
        let (tools, _) = makeTools(files: [existing])
        let result = tools.handle(name: "insert_after_heading",
                                  argumentsJSON: json(["name": "Ins", "heading": "A", "content": "inserted line"]))
        XCTAssertTrue(result.hasPrefix("wrote"), result)
        XCTAssertEqual(try read("Ins.md"), "# Title\nintro\n## A\ninserted line\nold a\n")
    }

    func testInsertAfterHeadingNotFound() throws {
        let existing = try writeFile("Ins.md", "## A\nbody\n")
        let (tools, _) = makeTools(files: [existing])
        XCTAssertEqual(tools.handle(name: "insert_after_heading",
                                    argumentsJSON: json(["name": "Ins", "heading": "Z", "content": "x"])),
                       "error: heading not found")
    }

    func testInsertAfterHeadingDocNotFound() {
        let (tools, _) = makeTools()
        XCTAssertEqual(tools.handle(name: "insert_after_heading",
                                    argumentsJSON: json(["name": "Ghost", "heading": "A", "content": "x"])),
                       "error: Ghost not found")
    }

    // MARK: - descriptors / unknown

    func testDescriptorsValidJSON() {
        for d in MindoAgentTools.docEditDescriptors {
            let data = Data(d.parametersJSON.utf8)
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data),
                             "invalid JSON schema for \(d.name)")
        }
        let names = Set(MindoAgentTools.docEditDescriptors.map { $0.name })
        XCTAssertEqual(names, ["create_document", "overwrite_document", "append_to_document",
                               "replace_section", "insert_after_heading"])
    }

    func testHandlerReturnsNilForUnknown() {
        let (tools, _) = makeTools()
        XCTAssertNil(tools.handleDocEdit("not_a_tool", ToolArgs([:])))
    }
}
