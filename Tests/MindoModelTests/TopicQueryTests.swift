import XCTest
@testable import MindoModel

final class TopicQueryTests: XCTestCase {
    private func sample() -> MindMap {
        let root = Topic(text: "Project")
        let a = root.addChild(text: "Design API")
        a.setProperty("priority", .number(1)); a.setProperty("done", .checkbox(false))
        a.setProperty("tags", .list(["urgent", "backend"]))
        let b = root.addChild(text: "Write docs")
        b.setProperty("priority", .number(3)); b.setProperty("done", .checkbox(true))
        b.setProperty("tags", .list(["docs"]))
        return MindMap(root: root)
    }

    func testPropertyTerm() {
        let m = sample()
        XCTAssertEqual(TopicQuery.evaluate("priority:1", in: m).map(\.text), ["Design API"])
        XCTAssertEqual(TopicQuery.evaluate("done:true", in: m).map(\.text), ["Write docs"])
    }

    func testTagShorthandAndTextTerm() {
        let m = sample()
        XCTAssertEqual(TopicQuery.evaluate("#urgent", in: m).map(\.text), ["Design API"])
        XCTAssertEqual(TopicQuery.evaluate("docs", in: m).map(\.text), ["Write docs"])  // text substring
    }

    func testImpliedAndAcrossTerms() {
        let m = sample()
        XCTAssertEqual(TopicQuery.evaluate("done:false priority:1", in: m).map(\.text), ["Design API"])
        XCTAssertTrue(TopicQuery.evaluate("done:false priority:3", in: m).isEmpty)
    }

    func testPropertyPresenceAndTagKey() {
        let m = sample()
        XCTAssertEqual(TopicQuery.evaluate("priority:", in: m).count, 2)         // has priority
        XCTAssertEqual(TopicQuery.evaluate("tag:docs", in: m).map(\.text), ["Write docs"])
    }

    func testBlankQueryMatchesNothing() {
        XCTAssertTrue(TopicQuery.evaluate("   ", in: sample()).isEmpty)
    }
}
