import XCTest
@testable import MindoCore

final class ScriptBuilderParserTests: XCTestCase {

    func testBuilderOutlineDepthsAndDecorators() throws {
        let program = try ScriptParser.parseProgram("""
        map "Launch Plan"
          Marketing
            Blog post | @fillColor: "#ffe0b2"
            Email blast
          Engineering
            Frontend
          Timeline
            {{ "Week " + str(1) }}
        """)
        XCTAssertEqual(program.count, 1)
        guard case .map(let m) = program[0] else { return XCTFail("expected map block") }
        XCTAssertEqual(m.name, "Launch Plan")
        XCTAssertEqual(m.lines.count, 7)

        // Depths follow indentation (2-space units): Marketing=1, Blog post=2 …
        XCTAssertEqual(m.lines.map(\.depth), [1, 2, 2, 1, 2, 1, 2])

        // Marketing → plain text.
        XCTAssertEqual(m.lines[0].body, .text([.literal("Marketing")]))

        // Blog post → text + a fillColor decorator (string value, '#' kept).
        XCTAssertEqual(m.lines[1].body, .text([.literal("Blog post")]))
        XCTAssertEqual(m.lines[1].decorators, [Decorator(key: "fillColor", value: .string("#ffe0b2"))])

        // Timeline child → a single interpolation piece.
        XCTAssertEqual(m.lines[6].body,
                       .text([.interp(.binary("+", .string("Week "), .call(callee: "str", args: [.number(1)])))]))
    }

    func testInterpolationMixedWithLiterals() throws {
        let program = try ScriptParser.parseProgram("""
        map "M"
          Week {{ str(1) }} plan
        """)
        guard case .map(let m) = program[0] else { return XCTFail() }
        XCTAssertEqual(m.lines[0].body, .text([
            .literal("Week "),
            .interp(.call(callee: "str", args: [.number(1)])),
            .literal(" plan"),
        ]))
    }

    func testEscapedPipeStaysLiteral() throws {
        let program = try ScriptParser.parseProgram("""
        map "M"
          a \\| b | @note: "x"
        """)
        guard case .map(let m) = program[0] else { return XCTFail() }
        XCTAssertEqual(m.lines[0].body, .text([.literal("a | b")]))
        XCTAssertEqual(m.lines[0].decorators.first?.key, "note")
    }

    func testPipeInsideDecoratorStringNotSplit() throws {
        let program = try ScriptParser.parseProgram(#"""
        map "M"
          x | @note: "a|b"
        """#)
        guard case .map(let m) = program[0] else { return XCTFail() }
        XCTAssertEqual(m.lines[0].decorators, [Decorator(key: "note", value: .string("a|b"))])
    }

    func testFromClause() throws {
        let program = try ScriptParser.parseProgram("""
        map "Refs"
          from $refs
        """)
        guard case .map(let m) = program[0] else { return XCTFail() }
        XCTAssertEqual(m.lines[0].body, .from("refs"))
    }

    func testMixedQueryThenBuilder() throws {
        // Spec example 5.
        let program = try ScriptParser.parseProgram("""
        ? backlinks "Architecture" | map .source.name | distinct | sortBy . as $refs

        map "Who references Architecture"
          from $refs
        """)
        XCTAssertEqual(program.count, 2)
        guard case .query(let q) = program[0] else { return XCTFail("query") }
        XCTAssertEqual(q.bind, "refs")
        guard case .map(let m) = program[1] else { return XCTFail("map") }
        XCTAssertEqual(m.name, "Who references Architecture")
        XCTAssertEqual(m.lines, [BuilderLine(depth: 1, body: .from("refs"), decorators: [])])
    }

    func testErrors() {
        XCTAssertThrowsError(try ScriptParser.parseProgram("map\n  x"))          // header needs a name
        XCTAssertThrowsError(try ScriptParser.parseProgram("  indented"))        // top-level indent
        XCTAssertThrowsError(try ScriptParser.parseProgram("map \"M\"\n  a | bad")) // decorator without @
    }
}
