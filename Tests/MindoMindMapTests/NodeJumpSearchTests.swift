import XCTest
import MindoModel
import MindoBase
import MindoCore
@testable import MindoMindMap

/// Go to Node search over a map riddled with same-named "Topic" nodes — the
/// reported pain. Breadcrumbs must disambiguate them, and matching the full
/// path must let an ancestor narrow the results.
final class NodeJumpSearchTests: XCTestCase {

    private func pathKey(_ item: OutlineItem) -> String {
        item.breadcrumb.isEmpty ? item.title : "\(item.breadcrumb) › \(item.title)"
    }

    private func map() -> MindMap {
        let m = MindMap()
        let root = Topic(text: "an"); m.root = root
        let shit = root.addChild(text: "shit")
        shit.addChild(text: "Topic")            // an › shit › Topic
        root.addChild(text: "Topic")            // an › Topic
        root.addChild(text: "topic1")
        let good = root.addChild(text: "good")
        good.addChild(text: "Topic")            // an › good › Topic
        return m
    }

    func testDuplicateTopicsGetDistinctBreadcrumbs() {
        let items = Outline.fromMindMap(map())
        let topics = items.filter { $0.title == "Topic" }
        XCTAssertEqual(topics.count, 3)
        let crumbs = Set(topics.map(\.breadcrumb))
        XCTAssertEqual(crumbs.count, 3, "each Topic has a distinct breadcrumb")
        XCTAssertTrue(crumbs.contains("an › shit"))
        XCTAssertTrue(crumbs.contains("an"))
        XCTAssertTrue(crumbs.contains("an › good"))
    }

    func testTopicQueryReturnsEveryTopic() {
        let items = Outline.fromMindMap(map())
        let hits = FuzzyMatch.rank(items, query: "topic") { pathKey($0) }
        let titles = hits.map { $0.item.title }
        XCTAssertEqual(titles.filter { $0 == "Topic" }.count, 3, "all three Topics match")
        XCTAssertTrue(titles.contains("topic1"))
    }

    func testAncestorNarrowsToOneTopic() {
        let items = Outline.fromMindMap(map())
        let hits = FuzzyMatch.rank(items, query: "shit topic") { pathKey($0) }
        let best = hits.first
        XCTAssertEqual(best?.item.title, "Topic")
        XCTAssertEqual(best?.item.breadcrumb, "an › shit",
                       "typing an ancestor pins the exact Topic")
    }
}
