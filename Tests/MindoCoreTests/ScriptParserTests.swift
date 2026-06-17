import XCTest
@testable import MindoCore

final class ScriptParserTests: XCTestCase {

    private func parse(_ s: String) throws -> ScriptNode { try ScriptParser.parseExpression(s) }

    // MARK: - Literals & primaries

    func testLiterals() throws {
        XCTAssertEqual(try parse("42"), .number(42))
        XCTAssertEqual(try parse("\"hi\""), .string("hi"))
        XCTAssertEqual(try parse("true"), .bool(true))
        XCTAssertEqual(try parse("false"), .bool(false))
        XCTAssertEqual(try parse("null"), .null)
        XCTAssertEqual(try parse("$refs"), .variable("refs"))
        XCTAssertEqual(try parse("nodes"), .identifier("nodes"))
    }

    func testArithmeticPrecedence() throws {
        // 1 + 2 * 3 == 1 + (2*3)
        XCTAssertEqual(try parse("1 + 2 * 3"),
                       .binary("+", .number(1), .binary("*", .number(2), .number(3))))
        // (1 + 2) * 3
        XCTAssertEqual(try parse("(1 + 2) * 3"),
                       .binary("*", .binary("+", .number(1), .number(2)), .number(3)))
    }

    func testComparisonAndLogical() throws {
        // a && b || c  ==  (a && b) || c
        XCTAssertEqual(try parse("a && b || c"),
                       .binary("||", .binary("&&", .identifier("a"), .identifier("b")), .identifier("c")))
        XCTAssertEqual(try parse("x == 1"), .binary("==", .identifier("x"), .number(1)))
    }

    func testWordOperators() throws {
        XCTAssertEqual(try parse(#".text matches "TODO""#),
                       .binary("matches", .member(.identity, "text"), .string("TODO")))
        XCTAssertEqual(try parse(#""a" in $list"#),
                       .binary("in", .string("a"), .variable("list")))
    }

    func testTernary() throws {
        XCTAssertEqual(try parse("a ? b : c"),
                       .ternary(.identifier("a"), .identifier("b"), .identifier("c")))
    }

    func testUnary() throws {
        XCTAssertEqual(try parse("!done"), .unary("!", .identifier("done")))
        XCTAssertEqual(try parse("-5"), .unary("-", .number(5)))
    }

    // MARK: - Postfix: identity, members, attributes, methods, index

    func testIdentityAndMembers() throws {
        XCTAssertEqual(try parse("."), .identity)
        XCTAssertEqual(try parse(".text"), .member(.identity, "text"))
        XCTAssertEqual(try parse(".source.name"),
                       .member(.member(.identity, "source"), "name"))
    }

    func testAttributeAccessorOnIdentity() throws {
        XCTAssertEqual(try parse(".@fillColor"), .attribute(.identity, "fillColor"))
    }

    func testMethodCallSugar() throws {
        // .text.upper()  →  method(member(identity,text), "upper", [])
        XCTAssertEqual(try parse(".text.upper()"),
                       .method(.member(.identity, "text"), "upper", []))
    }

    func testFreeCall() throws {
        XCTAssertEqual(try parse("len(.children)"),
                       .call(callee: "len", args: [.member(.identity, "children")]))
    }

    func testIndex() throws {
        XCTAssertEqual(try parse("$xs[0]"), .index(.variable("xs"), .number(0)))
    }

    // MARK: - Collections

    func testListLiteral() throws {
        XCTAssertEqual(try parse("[1, 2, 3]"), .list([.number(1), .number(2), .number(3)]))
        XCTAssertEqual(try parse("[]"), .list([]))
    }

    func testObjectLiteral() throws {
        XCTAssertEqual(try parse("{ broken: .target, in: .source }"),
                       .object([.init("broken", .member(.identity, "target")),
                                .init("in", .member(.identity, "source"))]))
        // string key
        XCTAssertEqual(try parse(#"{ "k": 1 }"#), .object([.init("k", .number(1))]))
    }

    func testNestedRealisticExpression() throws {
        // .alias != null ? .alias : .target   (from the group-by example)
        XCTAssertEqual(try parse(".alias != null ? .alias : .target"),
                       .ternary(.binary("!=", .member(.identity, "alias"), .null),
                                .member(.identity, "alias"),
                                .member(.identity, "target")))
    }

    // MARK: - Errors

    func testParseErrors() {
        XCTAssertThrowsError(try parse("(1 + 2"))      // missing )
        XCTAssertThrowsError(try parse("1 +"))         // dangling operator
        XCTAssertThrowsError(try parse("{ 1: 2 }"))    // numeric key
        XCTAssertThrowsError(try parse("1 2"))         // trailing token
        XCTAssertThrowsError(try parse(".text matches")) // dangling word op
    }
}
