import XCTest
import KepModel
import KepBase
@testable import KepMindMap

/// Exercises the ACTUAL search the Go to Node palette runs (`NodeJumpSearch`).
/// The reported pain: searching matched a node's ANCESTOR name and dragged in
/// every descendant. Matching is title-only; breadcrumb is display-only.
final class NodeJumpSearchTests: XCTestCase {

    private func items() -> [OutlineItem] {
        let m = MindMap()
        let root = Topic(text: "an"); m.root = root
        let shit = root.addChild(text: "shit")
        shit.addChild(text: "Topic")            // an › shit › Topic   (leaf)
        let topicParent = root.addChild(text: "Topic")   // an › Topic (a PARENT)
        topicParent.addChild(text: "从前有一座山")        // child of a Topic
        root.addChild(text: "topic1")
        let good = root.addChild(text: "good")
        good.addChild(text: "Topic")            // an › good › Topic   (leaf)
        return Outline.fromMindMap(m)
    }

    func testEmptyQueryListsEveryNode() {
        let r = NodeJumpSearch.results(items(), query: "")
        XCTAssertEqual(r.count, items().count, "no query → whole map (browse)")
    }

    func testTopicQueryReturnsEveryTopicByTitle() {
        let titles = NodeJumpSearch.results(items(), query: "topic").map { $0.item.title }
        XCTAssertEqual(titles.filter { $0 == "Topic" }.count, 3, "all three Topics match")
        XCTAssertTrue(titles.contains("topic1"))
    }

    /// The bug: a node whose ANCESTOR is named "Topic" must NOT match "topic".
    func testAncestorMatchDoesNotDragInDescendants() {
        let titles = NodeJumpSearch.results(items(), query: "topic").map { $0.item.title }
        XCTAssertFalse(titles.contains("从前有一座山"),
                       "a child of a Topic is not a topic — title-only matching excludes it")
    }

    func testDuplicatesShowDistinctBreadcrumbs() {
        let topics = items().filter { $0.title == "Topic" }
        let crumbs = Set(topics.map(\.breadcrumb))
        XCTAssertEqual(crumbs, ["an › shit", "an", "an › good"],
                       "same-named nodes still tell apart by their breadcrumb")
    }

    func testNoMatchIsEmpty() {
        XCTAssertTrue(NodeJumpSearch.results(items(), query: "zzzqx").isEmpty)
    }

    func testLimitCapsResults() {
        let m = MindMap(); let root = Topic(text: "r"); m.root = root
        for i in 0..<200 { root.addChild(text: "n\(i)") }
        let capped = NodeJumpSearch.results(Outline.fromMindMap(m), query: "n", limit: 50)
        XCTAssertEqual(capped.count, 50)
    }
}
