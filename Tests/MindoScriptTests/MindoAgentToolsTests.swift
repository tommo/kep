import XCTest
import MindoModel
@testable import MindoScript

final class MindoAgentToolsTests: XCTestCase {

    private let files = [
        URL(fileURLWithPath: "/ws/Architecture.md"),
        URL(fileURLWithPath: "/ws/Auth.md"),
        URL(fileURLWithPath: "/ws/Billing.md"),
    ]
    private func corpus() -> [(url: URL, text: String)] {
        [(files[1], "Auth uses [[Architecture]]."),
         (files[2], "Billing uses [[Architecture]].")]
    }
    private func tools(_ map: MindMap) -> MindoAgentTools {
        MindoAgentTools(map: map, corpus: corpus(), allFiles: files)
    }

    func testListDocs() {
        let r = tools(MindMap(root: Topic(text: "R"))).handle(name: "list_docs", argumentsJSON: "{}")
        XCTAssertEqual(r, "Architecture, Auth, Billing")
    }

    func testResolveLink() {
        let t = tools(MindMap(root: Topic(text: "R")))
        XCTAssertEqual(t.handle(name: "resolve_link", argumentsJSON: #"{"target":"Auth"}"#), "Auth")
        XCTAssertEqual(t.handle(name: "resolve_link", argumentsJSON: #"{"target":"Nope"}"#), "not found")
    }

    func testBacklinks() {
        let r = tools(MindMap(root: Topic(text: "R"))).handle(name: "backlinks", argumentsJSON: #"{"name":"Architecture"}"#)
        XCTAssertEqual(r, "Auth, Billing")
    }

    func testAddChildTopicMutatesMap() {
        let map = MindMap(root: Topic(text: "R"))
        let r = tools(map).handle(name: "add_child_topic", argumentsJSON: #"{"text":"New Idea"}"#)
        XCTAssertEqual(r, "added \"New Idea\"")
        XCTAssertEqual(map.root?.children.map(\.text), ["New Idea"])
    }

    func testRunLua() {
        let map = MindMap(root: Topic(text: "R"))
        let r = tools(map).handle(name: "run_lua",
                                  argumentsJSON: #"{"script":"mindo.addChild(mindo.root(), 'X'); return 'ok'"}"#)
        XCTAssertEqual(r, "ok")
        XCTAssertEqual(map.root?.children.map(\.text), ["X"])
    }

    func testMissingArgAndUnknownTool() {
        let t = tools(MindMap(root: Topic(text: "R")))
        XCTAssertTrue(t.handle(name: "resolve_link", argumentsJSON: "{}").hasPrefix("error:"))
        XCTAssertTrue(t.handle(name: "bogus", argumentsJSON: "{}").hasPrefix("error: unknown tool"))
    }

    func testDescriptorsCoverAllHandledTools() {
        XCTAssertEqual(Set(MindoAgentTools.descriptors.map(\.name)),
                       ["list_docs", "resolve_link", "backlinks", "add_child_topic", "run_lua"])
    }
}
