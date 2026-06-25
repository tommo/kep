import XCTest
import KepModel
@testable import KepScript

final class AgentToolsMindmapEditTests: XCTestCase {

    // MARK: - Fixtures

    /// Build a small map:
    ///   Root
    ///     A
    ///       A1
    ///       A2
    ///     B
    private func makeTools() -> (KepAgentTools, MindMap, AgentToolEffects) {
        let root = Topic(text: "Root")
        let a = root.addChild(text: "A")
        _ = a.addChild(text: "A1")
        _ = a.addChild(text: "A2")
        _ = root.addChild(text: "B")
        let map = MindMap()
        map.root = root
        let effects = AgentToolEffects()
        let tools = KepAgentTools(map: map, effects: effects)
        return (tools, map, effects)
    }

    private func json(_ dict: [String: Any]) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: dict), encoding: .utf8)!
    }

    private func call(_ tools: KepAgentTools, _ name: String, _ args: [String: Any]) -> String {
        tools.handle(name: name, argumentsJSON: json(args))
    }

    // MARK: - Descriptors

    func testDescriptorsAreValidJSONSchema() {
        let names = KepAgentTools.mindmapEditDescriptors.map { $0.name }
        XCTAssertEqual(Set(names), ["add_sibling_topic", "move_topic", "build_subtree", "sort_children"])
        for d in KepAgentTools.mindmapEditDescriptors {
            let obj = try? JSONSerialization.jsonObject(with: Data(d.parametersJSON.utf8)) as? [String: Any]
            XCTAssertNotNil(obj, "params for \(d.name) must be valid JSON")
            XCTAssertEqual(obj?["type"] as? String, "object")
            XCTAssertNotNil(obj?["properties"], "\(d.name) needs properties")
        }
    }

    func testUnknownToolReturnsNil() {
        let (tools, _, _) = makeTools()
        XCTAssertNil(tools.handleMindmapEdit("nope", ToolArgs([:])))
    }

    func testSortChildren() {
        let (tools, map, effects) = makeTools()
        // Root's children are A, B → already sorted; reverse first to test.
        _ = call(tools, "sort_children", ["query": "Root", "descending": true])
        XCTAssertEqual(map.root?.children.map(\.text), ["B", "A"])
        XCTAssertTrue(effects.mapMutated)
        _ = call(tools, "sort_children", ["path": ""])   // root by path, ascending
        XCTAssertEqual(map.root?.children.map(\.text), ["A", "B"])
    }

    func testSortChildrenNothingToSort() {
        let (tools, _, _) = makeTools()
        // "B" is a leaf → nothing to sort.
        XCTAssertTrue(call(tools, "sort_children", ["query": "B"]).contains("nothing to sort"))
    }

    // MARK: - add_sibling_topic

    func testAddSiblingAfter() {
        let (tools, map, effects) = makeTools()
        let result = call(tools, "add_sibling_topic", ["path": "0/0", "text": "A1b"])
        XCTAssertTrue(result.contains("added sibling \"A1b\""), result)
        let a = map.topic(atOutlinePath: "0")!
        XCTAssertEqual(a.children.map { $0.text }, ["A1", "A1b", "A2"])
        XCTAssertTrue(effects.mapMutated)
        // Reported path matches placement.
        XCTAssertTrue(result.contains("[0/1]"), result)
    }

    func testAddSiblingBefore() {
        let (tools, map, _) = makeTools()
        _ = call(tools, "add_sibling_topic", ["path": "0/1", "text": "A1c", "before": true])
        let a = map.topic(atOutlinePath: "0")!
        XCTAssertEqual(a.children.map { $0.text }, ["A1", "A1c", "A2"])
    }

    func testAddSiblingByQuery() {
        let (tools, map, _) = makeTools()
        _ = call(tools, "add_sibling_topic", ["query": "A2", "text": "A3"])
        let a = map.topic(atOutlinePath: "0")!
        XCTAssertEqual(a.children.map { $0.text }, ["A1", "A2", "A3"])
    }

    func testAddSiblingMissingText() {
        let (tools, _, _) = makeTools()
        XCTAssertTrue(call(tools, "add_sibling_topic", ["path": "0"]).hasPrefix("error"))
    }

    func testAddSiblingNotFound() {
        let (tools, _, effects) = makeTools()
        let r = call(tools, "add_sibling_topic", ["path": "9/9", "text": "x"])
        XCTAssertTrue(r.hasPrefix("error"), r)
        XCTAssertFalse(effects.mapMutated)
    }

    func testAddSiblingOnRootFails() {
        let (tools, _, effects) = makeTools()
        let r = call(tools, "add_sibling_topic", ["path": "", "text": "x"])
        XCTAssertTrue(r.hasPrefix("error"), r)
        XCTAssertFalse(effects.mapMutated)
    }

    // MARK: - move_topic

    func testMoveTopicAppend() {
        let (tools, map, effects) = makeTools()
        // Move A1 under B.
        let r = call(tools, "move_topic", ["path": "0/0", "to_parent": "B"])
        XCTAssertTrue(r.hasPrefix("moved"), r)
        let b = map.topic(atOutlinePath: "1")!
        XCTAssertEqual(b.children.map { $0.text }, ["A1"])
        let a = map.topic(atOutlinePath: "0")!
        XCTAssertEqual(a.children.map { $0.text }, ["A2"])
        XCTAssertTrue(effects.mapMutated)
    }

    func testMoveTopicWithIndex() {
        let (tools, map, _) = makeTools()
        // Move B under A at index 0.
        _ = call(tools, "move_topic", ["path": "1", "to_parent_path": "0", "index": 0])
        let a = map.topic(atOutlinePath: "0")!
        XCTAssertEqual(a.children.map { $0.text }, ["B", "A1", "A2"])
    }

    func testMoveTopicByQuery() {
        let (tools, map, _) = makeTools()
        _ = call(tools, "move_topic", ["query": "A1", "to_parent": "B"])
        let b = map.topic(atOutlinePath: "1")!
        XCTAssertEqual(b.children.map { $0.text }, ["A1"])
    }

    func testMoveTopicNotFound() {
        let (tools, _, effects) = makeTools()
        let r = call(tools, "move_topic", ["path": "9", "to_parent": "B"])
        XCTAssertTrue(r.hasPrefix("error"), r)
        XCTAssertFalse(effects.mapMutated)
    }

    func testMoveRootFails() {
        let (tools, _, _) = makeTools()
        XCTAssertTrue(call(tools, "move_topic", ["path": "", "to_parent": "A"]).hasPrefix("error"))
    }

    func testMoveMissingParent() {
        let (tools, _, _) = makeTools()
        XCTAssertTrue(call(tools, "move_topic", ["path": "0/0"]).hasPrefix("error"))
    }

    func testMoveParentNotFound() {
        let (tools, _, _) = makeTools()
        XCTAssertTrue(call(tools, "move_topic", ["path": "0/0", "to_parent": "ZZZ"]).hasPrefix("error"))
        XCTAssertTrue(call(tools, "move_topic", ["path": "0/0", "to_parent_path": "9/9"]).hasPrefix("error"))
    }

    func testMoveUnderSelfFails() {
        let (tools, _, effects) = makeTools()
        let r = call(tools, "move_topic", ["path": "0", "to_parent_path": "0"])
        XCTAssertTrue(r.hasPrefix("error"), r)
        XCTAssertFalse(effects.mapMutated)
    }

    func testMoveUnderDescendantFails() {
        let (tools, _, effects) = makeTools()
        // Move A under A1 (its own child) — cycle.
        let r = call(tools, "move_topic", ["path": "0", "to_parent_path": "0/0"])
        XCTAssertTrue(r.hasPrefix("error"), r)
        XCTAssertFalse(effects.mapMutated)
    }

    // MARK: - build_subtree

    func testBuildSubtreeUnderRootByDefault() {
        let (tools, map, effects) = makeTools()
        let outline = """
        Topic1
          Child1
          Child2
        Topic2
        """
        let r = call(tools, "build_subtree", ["outline": outline])
        XCTAssertTrue(r.contains("added 4 topics"), r)
        XCTAssertTrue(effects.mapMutated)
        let root = map.root!
        XCTAssertEqual(root.children.map { $0.text }, ["A", "B", "Topic1", "Topic2"])
        let t1 = root.children.first { $0.text == "Topic1" }!
        XCTAssertEqual(t1.children.map { $0.text }, ["Child1", "Child2"])
    }

    func testBuildSubtreeUnderNamedParent() {
        let (tools, map, _) = makeTools()
        let outline = """
        X
        \tY
        """
        _ = call(tools, "build_subtree", ["parent": "B", "outline": outline])
        let b = map.topic(atOutlinePath: "1")!
        XCTAssertEqual(b.children.map { $0.text }, ["X"])
        XCTAssertEqual(b.children[0].children.map { $0.text }, ["Y"])
    }

    func testBuildSubtreeUnderParentPath() {
        let (tools, map, _) = makeTools()
        _ = call(tools, "build_subtree", ["parent_path": "0", "outline": "Z"])
        let a = map.topic(atOutlinePath: "0")!
        XCTAssertEqual(a.children.map { $0.text }, ["A1", "A2", "Z"])
    }

    func testBuildSubtreeSkipsBlankLinesAndDeepNesting() {
        let (tools, map, _) = makeTools()
        let outline = """
        L0

          L1
            L2

        L0b
        """
        let r = call(tools, "build_subtree", ["parent_path": "1", "outline": outline])
        XCTAssertTrue(r.contains("added 4 topics"), r)
        let b = map.topic(atOutlinePath: "1")!
        XCTAssertEqual(b.children.map { $0.text }, ["L0", "L0b"])
        let l0 = b.children[0]
        XCTAssertEqual(l0.children.map { $0.text }, ["L1"])
        XCTAssertEqual(l0.children[0].children.map { $0.text }, ["L2"])
    }

    func testBuildSubtreeIrregularIndentationDoesNotCrash() {
        let (tools, map, _) = makeTools()
        // Jumps straight to deep indentation; should clamp, not crash.
        let outline = "   A\n          B\n c\n"
        let r = call(tools, "build_subtree", ["parent_path": "1", "outline": outline])
        XCTAssertTrue(r.contains("added 3 topics"), r)
        let b = map.topic(atOutlinePath: "1")!
        XCTAssertFalse(b.children.isEmpty)
    }

    func testBuildSubtreeMissingOutline() {
        let (tools, _, _) = makeTools()
        XCTAssertTrue(call(tools, "build_subtree", [:]).hasPrefix("error"))
    }

    func testBuildSubtreeBadParentPath() {
        let (tools, _, effects) = makeTools()
        let r = call(tools, "build_subtree", ["parent_path": "9/9", "outline": "X"])
        XCTAssertTrue(r.hasPrefix("error"), r)
        XCTAssertFalse(effects.mapMutated)
    }

    func testBuildSubtreeCreatesRootWhenEmpty() {
        let map = MindMap()
        map.root = nil
        let effects = AgentToolEffects()
        let tools = KepAgentTools(map: map, effects: effects)
        let r = tools.handle(name: "build_subtree", argumentsJSON: json(["outline": "Hello\n  World"]))
        XCTAssertTrue(r.contains("added 2 topics"), r)
        XCTAssertNotNil(map.root)
        XCTAssertEqual(map.root?.children.map { $0.text }, ["Hello"])
    }
}
