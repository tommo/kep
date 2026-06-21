import XCTest
@testable import MindoModel

final class MindMapTagsTests: XCTestCase {
    private func makeMap() -> MindMap {
        let root = Topic(text: "Root")
        let a = root.addChild(text: "A"); a.setProperty("tags", .list(["urgent", "work"]))
        let b = root.addChild(text: "B"); b.setProperty("tags", .list(["work"]))
        _ = root.addChild(text: "C")                                  // no tags
        let d = root.addChild(text: "D"); d.setProperty("tags", .list(["urgent", ""]))  // empty ignored
        return MindMap(root: root)
    }

    func testTagCountsSortedWithCounts() {
        let counts = MindMapTags.tagCounts(in: makeMap())
        XCTAssertEqual(counts.map(\.tag), ["urgent", "work"])
        XCTAssertEqual(counts.first { $0.tag == "urgent" }?.count, 2)
        XCTAssertEqual(counts.first { $0.tag == "work" }?.count, 2)
    }

    func testTopicsWithTag() {
        let map = makeMap()
        XCTAssertEqual(MindMapTags.topicsWithTag("urgent", in: map).map(\.text), ["A", "D"])
        XCTAssertEqual(MindMapTags.topicsWithTag("work", in: map).map(\.text), ["A", "B"])
        XCTAssertTrue(MindMapTags.topicsWithTag("missing", in: map).isEmpty)
    }

    func testEmptyTagsIgnored() {
        let t = Topic(text: "x"); t.setProperty("tags", .list(["", "  "]))
        // "  " is non-empty whitespace → counts as a tag; "" is dropped.
        XCTAssertEqual(MindMapTags.tags(of: t), ["  "])
    }
}
