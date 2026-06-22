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

    func testOrGroups() {
        let m = sample()
        // (priority:1) OR (priority:3) → both tasks.
        XCTAssertEqual(Set(TopicQuery.evaluate("priority:1 OR priority:3", in: m).map(\.text)),
                       ["Design API", "Write docs"])
    }

    func testNegation() {
        let m = sample()
        // has a priority but NOT done → Design API only.
        XCTAssertEqual(TopicQuery.evaluate("priority: -done:true", in: m).map(\.text), ["Design API"])
    }

    func testUnderScopesToBranch() {
        let root = Topic(text: "Root")
        let work = root.addChild(text: "Work")
        let t1 = work.addChild(text: "Ship release"); t1.setProperty("done", .checkbox(false))
        let home = root.addChild(text: "Home")
        let t2 = home.addChild(text: "Ship package"); t2.setProperty("done", .checkbox(false))
        let m = MindMap(root: root)
        // done:false under the Work branch → only the Work task.
        XCTAssertEqual(TopicQuery.evaluate("done:false under:Work", in: m).map(\.text), ["Ship release"])
        XCTAssertEqual(TopicQuery.evaluate("under:Home", in: m).map(\.text), ["Ship package"])
    }

    func testNumericComparisonOperators() {
        let m = sample()   // Design API priority 1, Write docs priority 3
        XCTAssertEqual(TopicQuery.evaluate("priority>=3", in: m).map(\.text), ["Write docs"])
        XCTAssertEqual(TopicQuery.evaluate("priority>1", in: m).map(\.text), ["Write docs"])
        XCTAssertEqual(TopicQuery.evaluate("priority<=1", in: m).map(\.text), ["Design API"])
        XCTAssertEqual(TopicQuery.evaluate("priority<3", in: m).map(\.text), ["Design API"])
        XCTAssertEqual(Set(TopicQuery.evaluate("priority>=1", in: m).map(\.text)), ["Design API", "Write docs"])
        XCTAssertTrue(TopicQuery.evaluate("priority>9", in: m).isEmpty)
        // Non-numeric / missing property → no match, not a crash.
        XCTAssertTrue(TopicQuery.evaluate("tags>1", in: m).isEmpty)
        XCTAssertTrue(TopicQuery.evaluate("missing>1", in: m).isEmpty)
        // Composes with AND.
        XCTAssertEqual(TopicQuery.evaluate("priority>=1 done:true", in: m).map(\.text), ["Write docs"])
    }

    func testComparisonDoesNotBreakColonTerms() {
        let m = sample()
        // A colon term whose value contains '>' stays a text match, not a comparison.
        XCTAssertTrue(TopicQuery.evaluate("text:a>b", in: m).isEmpty)
    }

    func testRegexTerm() {
        let m = sample()
        XCTAssertEqual(TopicQuery.evaluate("/^Design/", in: m).map(\.text), ["Design API"])
        XCTAssertTrue(TopicQuery.evaluate("/zzz/", in: m).isEmpty)
    }
}
