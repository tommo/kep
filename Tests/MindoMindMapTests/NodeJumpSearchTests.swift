import XCTest
import MindoModel
import MindoBase
@testable import MindoMindMap

/// Exercises the ACTUAL search the Go to Node palette runs (`NodeJumpSearch`,
/// the same call the view makes) over a map riddled with same-named "Topic"
/// nodes — the reported pain. No logic is reimplemented here.
final class NodeJumpSearchTests: XCTestCase {

    private func items() -> [OutlineItem] {
        let m = MindMap()
        let root = Topic(text: "an"); m.root = root
        let shit = root.addChild(text: "shit")
        shit.addChild(text: "Topic")            // an › shit › Topic
        root.addChild(text: "Topic")            // an › Topic
        root.addChild(text: "topic1")
        let good = root.addChild(text: "good")
        good.addChild(text: "Topic")            // an › good › Topic
        return Outline.fromMindMap(m)
    }

    func testEmptyQueryListsEveryNode() {
        let r = NodeJumpSearch.results(items(), query: "")
        XCTAssertEqual(r.count, items().count, "no query → whole map")
    }

    func testTopicQueryReturnsEveryTopic() {
        let r = NodeJumpSearch.results(items(), query: "topic")
        let titles = r.map { $0.item.title }
        XCTAssertEqual(titles.filter { $0 == "Topic" }.count, 3, "all three Topics match")
        XCTAssertTrue(titles.contains("topic1"))
    }

    func testDuplicatesShowDistinctPaths() {
        let topics = items().filter { $0.title == "Topic" }
        let keys = Set(topics.map { NodeJumpSearch.pathKey($0) })
        XCTAssertEqual(keys, ["an › shit › Topic", "an › Topic", "an › good › Topic"],
                       "each duplicate renders a distinct, navigable path")
    }

    func testAncestorNarrowsToOneTopic() {
        let r = NodeJumpSearch.results(items(), query: "shit topic")
        XCTAssertEqual(r.first.map { NodeJumpSearch.pathKey($0.item) }, "an › shit › Topic",
                       "typing an ancestor pins the exact Topic")
    }

    func testNoMatchIsEmpty() {
        XCTAssertTrue(NodeJumpSearch.results(items(), query: "zzzqx").isEmpty)
    }

    func testLimitCapsResults() {
        // 200 sibling nodes, capped output.
        let m = MindMap(); let root = Topic(text: "r"); m.root = root
        for i in 0..<200 { root.addChild(text: "n\(i)") }
        let capped = NodeJumpSearch.results(Outline.fromMindMap(m), query: "n", limit: 50)
        XCTAssertEqual(capped.count, 50)
    }
}
