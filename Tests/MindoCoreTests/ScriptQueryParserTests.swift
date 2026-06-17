import XCTest
@testable import MindoCore

final class ScriptQueryParserTests: XCTestCase {

    private func q(_ s: String) throws -> QueryBlock { try ScriptParser.parseQuery(s) }

    func testSimpleNodesWhereSet() throws {
        // Spec example 2 (batch-edit).
        let block = try q("""
        ? nodes
          | where .text matches "(?i)\\bTODO\\b"
          | set @fillColor = "#ffcdd2"
          | rename "[urgent] " + .text
        """)
        XCTAssertEqual(block.source, .nodes(nil))
        XCTAssertEqual(block.stages.count, 3)
        guard case .whereKeep = block.stages[0] else { return XCTFail("stage0 where") }
        guard case .setAttr(let k, _) = block.stages[1] else { return XCTFail("stage1 set") }
        XCTAssertEqual(k, "fillColor")
        guard case .rename = block.stages[2] else { return XCTFail("stage2 rename") }
        XCTAssertNil(block.bind)
    }

    func testBacklinksDistinctSortCollect() throws {
        // Spec example 3.
        let block = try q(#"? backlinks "Architecture" | map .source.name | distinct | sortBy . | collect"#)
        XCTAssertEqual(block.source, .backlinks(.string("Architecture")))
        XCTAssertEqual(block.stages, [
            .mapEach(.member(.member(.identity, "source"), "name")),
            .distinct,
            .sortBy(.identity),
            .collect,
        ])
    }

    func testNodesNamedMap() throws {
        XCTAssertEqual(try q(#"? nodes "Plan""#).source, .nodes("Plan"))
    }

    func testLinksDeadLinkQuery() throws {
        // Spec example 4: links | where resolveDoc(.target) == null | map {…} | collect
        let block = try q(#"? links | where resolveDoc(.target) == null | map { broken: .target, in: .source } | collect"#)
        XCTAssertEqual(block.source, .links(nil))
        XCTAssertEqual(block.stages.count, 3)
        guard case .whereKeep = block.stages[0] else { return XCTFail() }
        guard case .mapEach(.object(let entries)) = block.stages[1] else { return XCTFail("map object") }
        XCTAssertEqual(entries.map(\.key), ["broken", "in"])
        guard case .collect = block.stages[2] else { return XCTFail() }
    }

    func testTrailingAsBind() throws {
        // Spec example 5's query half.
        let block = try q("? backlinks \"Architecture\" | map .source.name | distinct | sortBy . as $refs")
        XCTAssertEqual(block.bind, "refs")
        XCTAssertEqual(block.stages.count, 3)   // map, distinct, sortBy — `as` is not a stage
    }

    func testLimitAndDepthFilter() throws {
        let block = try q("? nodes | where .depth > 3 | limit 5")
        XCTAssertEqual(block.stages.count, 2)
        guard case .limit(let n) = block.stages[1] else { return XCTFail("limit") }
        XCTAssertEqual(n, 5)
    }

    func testGroupReducer() throws {
        // Spec example 7.
        let block = try q(#"? backlinks "Roadmap" | group (.alias != null ? .alias : .target) | collect"#)
        guard case .group(.ternary) = block.stages[0] else { return XCTFail("group ternary") }
    }

    func testFromSource() throws {
        XCTAssertEqual(try q("? from $refs").source, .from("refs"))
    }

    func testProgramMultipleQueries() throws {
        let program = try ScriptParser.parseProgram("""
        ? nodes | count
        ? docs | collect
        """)
        XCTAssertEqual(program.count, 2)
    }

    func testErrors() {
        XCTAssertThrowsError(try q("? bogus | collect"))        // unknown source
        XCTAssertThrowsError(try q("? nodes | frobnicate"))     // unknown stage
        XCTAssertThrowsError(try q("? nodes | set fillColor = 1")) // missing @
        XCTAssertThrowsError(try q("nodes | count"))            // missing ?
    }
}
