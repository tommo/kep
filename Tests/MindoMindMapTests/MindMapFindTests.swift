import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

@MainActor
final class MindMapFindTests: XCTestCase {

    private func makeFixture() -> (MindMapView, root: Topic, alpha: Topic, betaTopic: Topic, beta2: Topic) {
        let map = MindMap()
        let root = Topic(text: "Project")
        map.root = root
        let a = root.addChild(text: "Alpha goal")
        let b = root.addChild(text: "Beta milestone")
        let b2 = b.addChild(text: "Beta sub-task")
        let (view, _) = makeHeadlessMindMapWithUndo(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        return (view, root, a, b, b2)
    }

    func testFindMatchesWalksTreePreOrder() {
        let (view, _, _, b, b2) = makeFixture()
        let hits = view.findMatches(query: "beta")
        XCTAssertEqual(hits.count, 2)
        // Pre-order: root → Alpha → Beta milestone → Beta sub-task → ...
        XCTAssertTrue(hits[0].topic === b)
        XCTAssertTrue(hits[1].topic === b2)
    }

    func testFindIsCaseInsensitiveByDefault() {
        let (view, _, _, _, _) = makeFixture()
        XCTAssertEqual(view.findMatches(query: "BETA").count, 2)
        XCTAssertEqual(view.findMatches(query: "BETA", caseSensitive: true).count, 0)
    }

    func testEmptyOrWhitespaceQueryReturnsNothing() {
        let (view, _, _, _, _) = makeFixture()
        XCTAssertTrue(view.findMatches(query: "").isEmpty)
        XCTAssertTrue(view.findMatches(query: "   ").isEmpty)
    }

    func testReplaceAllUpdatesEveryMatchAndReturnsCount() {
        let (view, _, _, b, b2) = makeFixture()
        let n = view.replaceAll(query: "beta", with: "Gamma")
        XCTAssertEqual(n, 2)
        XCTAssertEqual(b.text, "Gamma milestone")
        XCTAssertEqual(b2.text, "Gamma sub-task")
        // Subsequent search for the old token returns nothing.
        XCTAssertTrue(view.findMatches(query: "beta").isEmpty)
    }

    func testReplaceAllReturnsZeroForUnknownQuery() {
        let (view, _, _, _, _) = makeFixture()
        XCTAssertEqual(view.replaceAll(query: "definitely-not-here", with: "x"), 0)
    }
}
