import XCTest
import KepModel
@testable import KepScript

final class KepAgentToolsTests: XCTestCase {

    private let files = [
        URL(fileURLWithPath: "/ws/Architecture.md"),
        URL(fileURLWithPath: "/ws/Auth.md"),
        URL(fileURLWithPath: "/ws/Billing.md"),
    ]
    private func corpus() -> [(url: URL, text: String)] {
        [(files[1], "Auth uses [[Architecture]]."),
         (files[2], "Billing uses [[Architecture]].")]
    }
    private func tools(_ map: MindMap) -> KepAgentTools {
        KepAgentTools(map: map, corpus: corpus(), allFiles: files)
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

    func testAddChildTopicUnderRoot() {
        let map = MindMap(root: Topic(text: "R"))
        let r = tools(map).handle(name: "add_child_topic", argumentsJSON: #"{"text":"New Idea"}"#)
        XCTAssertEqual(r, "added \"New Idea\" under \"R\" at [0]")
        XCTAssertEqual(map.root?.children.map(\.text), ["New Idea"])
    }

    func testAddChildTopicUnderNamedParent() {
        let map = MindMap(root: Topic(text: "Root"))
        let eq = map.root!.addChild(text: "Equipment")
        let r = tools(map).handle(name: "add_child_topic",
                                  argumentsJSON: #"{"text":"Grinder","parent":"equip"}"#)
        XCTAssertEqual(r, "added \"Grinder\" under \"Equipment\" at [0/0]")
        XCTAssertEqual(eq.children.map(\.text), ["Grinder"])
        // No matching parent → error, no mutation.
        XCTAssertTrue(tools(map).handle(name: "add_child_topic",
                                        argumentsJSON: #"{"text":"X","parent":"nope"}"#).hasPrefix("error:"))
    }

    func testRunLua() {
        let map = MindMap(root: Topic(text: "R"))
        let r = tools(map).handle(name: "run_lua",
                                  argumentsJSON: #"{"script":"kep.addChild(kep.root(), 'X'); return 'ok'"}"#)
        XCTAssertEqual(r, "ok")
        XCTAssertEqual(map.root?.children.map(\.text), ["X"])
    }

    func testMissingArgAndUnknownTool() {
        let t = tools(MindMap(root: Topic(text: "R")))
        XCTAssertTrue(t.handle(name: "resolve_link", argumentsJSON: "{}").hasPrefix("error:"))
        XCTAssertTrue(t.handle(name: "bogus", argumentsJSON: "{}").hasPrefix("error: unknown tool"))
    }

    func testRenameTopic() {
        let map = MindMap(root: Topic(text: "Root"))
        let a = map.root!.addChild(text: "Equipment")
        let r = tools(map).handle(name: "rename_topic", argumentsJSON: #"{"query":"equip","text":"Gear"}"#)
        XCTAssertEqual(r, "renamed \"Equipment\" → \"Gear\"")
        XCTAssertEqual(a.text, "Gear")
    }

    func testRemoveTopic() {
        let map = MindMap(root: Topic(text: "Root"))
        _ = map.root!.addChild(text: "keep")
        _ = map.root!.addChild(text: "drop")
        _ = tools(map).handle(name: "remove_topic", argumentsJSON: #"{"query":"drop"}"#)
        XCTAssertEqual(map.root?.children.map(\.text), ["keep"])
        // Can't remove root.
        XCTAssertTrue(tools(map).handle(name: "remove_topic", argumentsJSON: #"{"query":"Root"}"#).hasPrefix("error:"))
    }

    func testSetTopicAttr() {
        let map = MindMap(root: Topic(text: "Root"))
        let a = map.root!.addChild(text: "Important")
        _ = tools(map).handle(name: "set_topic_attr",
                              argumentsJSON: ##"{"query":"import","key":"fillColor","value":"#ffcdd2"}"##)
        XCTAssertEqual(a.attribute("fillColor"), "#ffcdd2")
    }

    func testGetSubtreeWithAbsolutePathsAndDepthCap() {
        let map = MindMap(root: Topic(text: "Espresso"))
        let eq = map.root!.addChild(text: "Equipment")          // [0]
        let grinder = eq.addChild(text: "Grinder")              // [0/0]
        _ = grinder.addChild(text: "Burr")                      // [0/0/0]
        _ = map.root!.addChild(text: "Beans")                   // [1]

        // Full subtree rooted at Equipment, absolute paths preserved.
        XCTAssertEqual(tools(map).handle(name: "get_subtree", argumentsJSON: #"{"query":"Equipment"}"#),
                       "[0] Equipment\n  [0/0] Grinder\n    [0/0/0] Burr\n")
        // Depth-capped to 1 level below the target.
        XCTAssertEqual(tools(map).handle(name: "get_subtree", argumentsJSON: #"{"path":"0","depth":1}"#),
                       "[0] Equipment\n  [0/0] Grinder\n")
        // Unknown target → error.
        XCTAssertTrue(tools(map).handle(name: "get_subtree", argumentsJSON: #"{"query":"zzz"}"#).hasPrefix("error:"))
    }

    func testGetMindmapOutline() {
        let map = MindMap(root: Topic(text: "Espresso"))
        let eq = map.root!.addChild(text: "Equipment")
        _ = eq.addChild(text: "Grinder")
        _ = map.root!.addChild(text: "Beans")
        XCTAssertEqual(tools(map).handle(name: "get_mindmap", argumentsJSON: "{}"),
                       "[] Espresso\n  [0] Equipment\n    [0/0] Grinder\n  [1] Beans\n")
    }

    func testFindTopics() {
        let map = MindMap(root: Topic(text: "Espresso"))
        let r = map.root!
        let eq = r.addChild(text: "Equipment")
        _ = eq.addChild(text: "Espresso Machine")
        _ = r.addChild(text: "Beans")
        let out = tools(map).handle(name: "find_topics", argumentsJSON: #"{"query":"espresso"}"#)
        XCTAssertEqual(Set(out.split(separator: "\n").map(String.init)), ["[] Espresso", "[0/0] Espresso Machine"])
        XCTAssertEqual(tools(map).handle(name: "find_topics", argumentsJSON: #"{"query":"zzz"}"#), "(none)")
    }

    func testReadDocument() {
        let t = tools(MindMap(root: Topic(text: "R")))
        XCTAssertEqual(t.handle(name: "read_document", argumentsJSON: #"{"name":"Auth"}"#),
                       "Auth uses [[Architecture]].")
        XCTAssertEqual(t.handle(name: "read_document", argumentsJSON: #"{"name":"Nope"}"#), "not found")
    }

    func testDescriptorsAreUniqueAndValidJSON() {
        let names = KepAgentTools.descriptors.map(\.name)
        // No duplicate tool names across the aggregated groups.
        XCTAssertEqual(names.count, Set(names).count, "duplicate tool name in descriptors")
        // Every descriptor advertises a valid JSON-Schema params object.
        for d in KepAgentTools.descriptors {
            let obj = try? JSONSerialization.jsonObject(with: Data(d.parametersJSON.utf8))
            XCTAssertNotNil(obj as? [String: Any], "\(d.name) has invalid parametersJSON")
        }
    }

    func testEveryDescriptorIsHandled() {
        // A handled tool returns non-nil (even an "error: …") for empty args;
        // an unknown tool falls through to the unknown-tool message.
        let tools = self.tools(MindMap(root: Topic(text: "R")))
        for d in KepAgentTools.descriptors {
            let r = tools.handle(name: d.name, argumentsJSON: "{}")
            XCTAssertFalse(r.hasPrefix("error: unknown tool"),
                           "\(d.name) is advertised but not handled")
        }
        // Sanity: the suite really grew well beyond the original 11 core tools.
        XCTAssertGreaterThanOrEqual(KepAgentTools.descriptors.count, 25)
    }
}
