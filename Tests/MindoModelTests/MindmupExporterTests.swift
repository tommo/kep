import XCTest
@testable import MindoModel

final class MindmupExporterTests: XCTestCase {

    // MARK: - Shape

    func testEmptyMapEmitsRootShellWithEmptyMapTitle() throws {
        let json = MindmupExporter.export(MindMap())
        let parsed = try parseObject(json)
        XCTAssertEqual(parsed["formatVersion"] as? Int, 3)
        XCTAssertEqual(parsed["id"] as? String, "root")
        XCTAssertEqual(parsed["title"] as? String, "Empty map")
        XCTAssertTrue((parsed["ideas"] as? [String: Any])?.isEmpty == true)
    }

    func testRootIdeaIsKey1WithRootTitle() throws {
        let map = MindMap()
        map.root = Topic(text: "Root")
        let parsed = try parseObject(MindmupExporter.export(map))
        XCTAssertEqual(parsed["title"] as? String, "Root")
        let ideas = parsed["ideas"] as? [String: Any]
        let one = ideas?["1"] as? [String: Any]
        XCTAssertEqual(one?["title"] as? String, "Root")
        XCTAssertEqual(one?["id"] as? Int, 1)
    }

    // MARK: - Hierarchy + leftSide convention

    func testChildrenIncrementFromOne() throws {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        _ = root.addChild(text: "A")
        _ = root.addChild(text: "B")
        let parsed = try parseObject(MindmupExporter.export(map))
        let one = (parsed["ideas"] as? [String: Any])?["1"] as? [String: Any]
        let kids = one?["ideas"] as? [String: Any]
        XCTAssertEqual((kids?["1"] as? [String: Any])?["title"] as? String, "A")
        XCTAssertEqual((kids?["2"] as? [String: Any])?["title"] as? String, "B")
    }

    func testLeftSideRootChildGetsNegativeKey() throws {
        // A leftSide=true child on the root should appear under a
        // negative key — that's how Mindmup positions left-of-root
        // topics (and how our importer picks the side back up).
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let leftKid = root.addChild(text: "Left")
        leftKid.setAttribute(TopicAttribute.leftSide, "true")
        _ = root.addChild(text: "Right")
        let parsed = try parseObject(MindmupExporter.export(map))
        let kids = ((parsed["ideas"] as? [String: Any])?["1"] as? [String: Any])?["ideas"] as? [String: Any]
        XCTAssertEqual((kids?["-1"] as? [String: Any])?["title"] as? String, "Left")
        XCTAssertEqual((kids?["1"] as? [String: Any])?["title"] as? String, "Right")
    }

    func testLeftSideOnlyRecognizedOnRoot() throws {
        // leftSide is meaningful only for the root's direct children.
        // A leftSide attribute on a deeper node must NOT introduce
        // negative keys — Mindmup ignores it there too.
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let mid = root.addChild(text: "Mid")
        let leftLeaf = mid.addChild(text: "Leaf")
        leftLeaf.setAttribute(TopicAttribute.leftSide, "true")
        let parsed = try parseObject(MindmupExporter.export(map))
        let mids = ((parsed["ideas"] as? [String: Any])?["1"] as? [String: Any])?["ideas"] as? [String: Any]
        let leaves = (mids?["1"] as? [String: Any])?["ideas"] as? [String: Any]
        XCTAssertNotNil(leaves?["1"])
        XCTAssertNil(leaves?["-1"])
    }

    // MARK: - Extras

    func testNoteEmittedUnderAttrNote() throws {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        root.setExtra(ExtraNote(text: "hello"))
        let parsed = try parseObject(MindmupExporter.export(map))
        let one = (parsed["ideas"] as? [String: Any])?["1"] as? [String: Any]
        let attr = one?["attr"] as? [String: Any]
        let note = attr?["note"] as? [String: Any]
        XCTAssertEqual(note?["text"] as? String, "hello")
        XCTAssertEqual(note?["index"] as? Int, 3)
    }

    func testLinkAndFileExtrasGoIntoAttachmentHTML() {
        let html = MindmupExporter.attachmentHTML(
            link: ExtraLink(uri: "https://example.com"),
            file: ExtraFile(uri: "/tmp/foo.txt")
        )
        XCTAssertTrue(html.contains("FILE: <a href=\"/tmp/foo.txt\">/tmp/foo.txt</a><br>"))
        XCTAssertTrue(html.contains("LINK: <a href=\"https://example.com\">https://example.com</a><br>"))
    }

    func testNoExtrasMeansNoAttachmentField() throws {
        let map = MindMap()
        map.root = Topic(text: "Root")
        let parsed = try parseObject(MindmupExporter.export(map))
        let one = (parsed["ideas"] as? [String: Any])?["1"] as? [String: Any]
        XCTAssertNil(one?["attachment"])
    }

    // MARK: - Round-trip

    func testRoundTripThroughImporterPreservesTitlesAndHierarchy() throws {
        // The whole point of writing this exporter alongside the
        // existing importer is that they can hand off to each other
        // for a workspace edit. Verify the obvious shape survives.
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "Alpha")
        _ = a.addChild(text: "A1")
        _ = root.addChild(text: "Beta")

        let json = MindmupExporter.export(map)
        let imported = try MindmupImporter.parse(json)
        XCTAssertEqual(imported.root?.text, "Root")
        XCTAssertEqual(imported.root?.children.map(\.text).sorted(), ["Alpha", "Beta"])
        XCTAssertEqual(imported.root?.children.first(where: { $0.text == "Alpha" })?
                            .children.map(\.text), ["A1"])
    }

    // MARK: - Helpers

    private func parseObject(_ s: String) throws -> [String: Any] {
        let data = s.data(using: .utf8)!
        let any = try JSONSerialization.jsonObject(with: data, options: [])
        return any as! [String: Any]
    }
}
