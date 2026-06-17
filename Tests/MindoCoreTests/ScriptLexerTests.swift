import XCTest
@testable import MindoCore

final class ScriptValueTests: XCTestCase {

    func testTruthiness() {
        XCTAssertFalse(ScriptValue.null.isTruthy)
        XCTAssertFalse(ScriptValue.bool(false).isTruthy)
        XCTAssertTrue(ScriptValue.bool(true).isTruthy)
        // CEL/jq: 0, "", [], {} are all truthy
        XCTAssertTrue(ScriptValue.number(0).isTruthy)
        XCTAssertTrue(ScriptValue.string("").isTruthy)
        XCTAssertTrue(ScriptValue.list([]).isTruthy)
        XCTAssertTrue(ScriptValue.object([]).isTruthy)
    }

    func testStringifyNumbersDropTrailingZero() {
        XCTAssertEqual(ScriptValue.number(3).stringified, "3")
        XCTAssertEqual(ScriptValue.number(-7).stringified, "-7")
        XCTAssertEqual(ScriptValue.number(2.5).stringified, "2.5")
    }

    func testStringifyContainers() {
        XCTAssertEqual(ScriptValue.list([.number(1), .string("a")]).stringified, "[1, a]")
        XCTAssertEqual(ScriptValue.object([.init("k", .bool(true))]).stringified, "{k: true}")
        XCTAssertEqual(ScriptValue.null.stringified, "null")
        XCTAssertEqual(ScriptValue.handle(.init(kind: .topic, id: 4)).stringified, "<topic#4>")
    }

    func testEquatableObjectOrderSensitive() {
        let a = ScriptValue.object([.init("x", .number(1)), .init("y", .number(2))])
        let b = ScriptValue.object([.init("y", .number(2)), .init("x", .number(1))])
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, ScriptValue.object([.init("x", .number(1)), .init("y", .number(2))]))
    }
}

final class ScriptLexerTests: XCTestCase {

    private func kinds(_ src: String) throws -> [ScriptToken.Kind] {
        try ScriptLexer.tokenize(src).map(\.kind)
    }

    func testEmptyIsJustEof() throws {
        XCTAssertEqual(try kinds(""), [.eof])
    }

    func testNumbers() throws {
        XCTAssertEqual(try kinds("3 2.5 10"), [.number(3), .number(2.5), .number(10), .eof])
        // exponent
        XCTAssertEqual(try kinds("1e3 2.0e-2"), [.number(1000), .number(0.02), .eof])
        // a trailing dot is NOT part of the number (it's a dot token)
        XCTAssertEqual(try kinds("3.x"), [.number(3), .dot, .ident("x"), .eof])
    }

    func testIdentsVariablesAndAttributes() throws {
        XCTAssertEqual(try kinds("nodes where $refs"),
                       [.ident("nodes"), .ident("where"), .variable("refs"), .eof])
        XCTAssertEqual(try kinds(".@fillColor"), [.dot, .at, .ident("fillColor"), .eof])
    }

    func testOperators() throws {
        XCTAssertEqual(try kinds("== != <= >= < > && || ! + - * / %"),
                       [.eq, .neq, .lte, .gte, .lt, .gt, .andAnd, .orOr, .bang,
                        .plus, .minus, .star, .slash, .percent, .eof])
    }

    func testPipeVsOr() throws {
        XCTAssertEqual(try kinds("a | b || c"),
                       [.ident("a"), .pipe, .ident("b"), .orOr, .ident("c"), .eof])
    }

    func testPunctuationAndBraces() throws {
        XCTAssertEqual(try kinds("{ a: [1], }"),
                       [.lbrace, .ident("a"), .colon, .lbracket, .number(1), .rbracket, .comma, .rbrace, .eof])
    }

    func testStringEscapes() throws {
        let toks = try ScriptLexer.tokenize(#""line\n\ttab \"q\" A""#)
        XCTAssertEqual(toks.first?.kind, .string("line\n\ttab \"q\" A"))
    }

    func testTripleQuotedRawString() throws {
        let src = "\"\"\"a\nb \"c\" \\n\"\"\""
        XCTAssertEqual(try ScriptLexer.tokenize(src).first?.kind, .string("a\nb \"c\" \\n"))
    }

    func testCommentsAndNewlines() throws {
        XCTAssertEqual(try kinds("a # trailing\nb"),
                       [.ident("a"), .newline, .ident("b"), .eof])
    }

    func testSourcePositions() throws {
        let toks = try ScriptLexer.tokenize("a\n  b")
        XCTAssertEqual(toks[0].at, SourceRange(line: 1, col: 1))   // a
        XCTAssertEqual(toks[2].at, SourceRange(line: 2, col: 3))   // b after 2 spaces
    }

    func testQueryLineLexes() throws {
        XCTAssertEqual(try kinds(#"? nodes | where .text == "x""#),
                       [.question, .ident("nodes"), .pipe, .ident("where"),
                        .dot, .ident("text"), .eq, .string("x"), .eof])
    }

    func testLexErrors() {
        XCTAssertThrowsError(try ScriptLexer.tokenize("\"unterminated"))
        XCTAssertThrowsError(try ScriptLexer.tokenize("$ "))
        XCTAssertThrowsError(try ScriptLexer.tokenize("\"bad\\x\""))
        XCTAssertThrowsError(try ScriptLexer.tokenize("&"))
    }
}
