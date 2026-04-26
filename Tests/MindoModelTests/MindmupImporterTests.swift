import XCTest
@testable import MindoModel

final class MindmupImporterTests: XCTestCase {

    func testRootTitleAndChildOrder() throws {
        let json = #"""
        {
          "title": "Root",
          "ideas": {
            "1": { "title": "First" },
            "2": { "title": "Second" },
            "3": { "title": "Third" }
          }
        }
        """#
        let map = try MindmupImporter.parse(json)
        XCTAssertEqual(map.root?.text, "Root")
        XCTAssertEqual(map.root?.children.map(\.text), ["First", "Second", "Third"])
    }

    func testNestedSubtree() throws {
        let json = #"""
        {
          "title": "Root",
          "ideas": {
            "1": { "title": "A", "ideas": { "1": { "title": "A1" }, "2": { "title": "A2" } } }
          }
        }
        """#
        let map = try MindmupImporter.parse(json)
        XCTAssertEqual(map.root?.children.first?.children.map(\.text), ["A1", "A2"])
    }

    func testNegativeWeightStampsLeftSide() throws {
        // Mindmup convention: negative ordering keys land on the left of root.
        let json = #"""
        {
          "title": "Root",
          "ideas": {
            "-1": { "title": "Left" },
            "1":  { "title": "Right" }
          }
        }
        """#
        let map = try MindmupImporter.parse(json)
        let left = map.root?.children.first { $0.text == "Left" }
        let right = map.root?.children.first { $0.text == "Right" }
        XCTAssertEqual(left?.attribute(TopicAttribute.leftSide), "true")
        XCTAssertNil(right?.attribute(TopicAttribute.leftSide))
    }

    func testNonRootNegativeWeightDoesNotMarkLeft() throws {
        // Only root children carry the layout side; deeper levels don't
        // need it (they inherit from their root ancestor's branch).
        let json = #"""
        { "title": "R", "ideas": { "1": { "title": "A", "ideas": { "-1": { "title": "X" } } } } }
        """#
        let map = try MindmupImporter.parse(json)
        let x = map.root?.children.first?.children.first
        XCTAssertEqual(x?.text, "X")
        XCTAssertNil(x?.attribute(TopicAttribute.leftSide))
    }

    func testSortsByNumericKeyNotLexicographic() throws {
        // "10" sorts before "2" lexicographically — must use numeric.
        let json = #"""
        {
          "title": "R",
          "ideas": {
            "2":  { "title": "B" },
            "10": { "title": "C" },
            "1":  { "title": "A" }
          }
        }
        """#
        let map = try MindmupImporter.parse(json)
        XCTAssertEqual(map.root?.children.map(\.text), ["A", "B", "C"])
    }

    func testEmptyIdeasDictGivesLeafRoot() throws {
        let map = try MindmupImporter.parse(#"{ "title": "Solo", "ideas": {} }"#)
        XCTAssertEqual(map.root?.text, "Solo")
        XCTAssertTrue(map.root?.children.isEmpty ?? false)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try MindmupImporter.parse("not json"))
    }

    func testNonObjectRootThrows() {
        XCTAssertThrowsError(try MindmupImporter.parse("[1, 2, 3]"))
    }

    func testMissingTitleBecomesEmptyText() throws {
        let map = try MindmupImporter.parse(#"{ "ideas": { "1": { "title": "A" } } }"#)
        XCTAssertEqual(map.root?.text, "")
        XCTAssertEqual(map.root?.children.first?.text, "A")
    }
}
