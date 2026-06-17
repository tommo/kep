import Foundation

/// Recursive-descent + precedence-climbing parser for MindoScript's expression
/// sublanguage. Block/builder/query line parsing is added separately; this
/// parses a single `Expr` (used by query stages, decorators, and `{{ }}`).
///
/// Word operators (`matches`/`in`/`contains`) and literals (`true`/`false`/
/// `null`) arrive as `.ident` tokens from the lexer and are resolved here.
public struct ScriptParser {
    private let tokens: [ScriptToken]
    private var i = 0

    public init(_ tokens: [ScriptToken]) { self.tokens = tokens }

    /// Parse `source` as one expression. Trailing newline/eof is allowed; any
    /// other leftover token is an error.
    public static func parseExpression(_ source: String) throws -> ScriptNode {
        var parser = ScriptParser(try ScriptLexer.tokenize(source))
        let node = try parser.expression()
        parser.skipNewlines()
        if case .eof = parser.peek.kind {} else {
            throw ScriptError.parse("unexpected trailing token", at: parser.peek.at)
        }
        return node
    }

    // MARK: - Cursor

    private var peek: ScriptToken { tokens[i] }
    private func peek2() -> ScriptToken.Kind? { i + 1 < tokens.count ? tokens[i + 1].kind : nil }
    @discardableResult private mutating func advance() -> ScriptToken {
        let t = tokens[i]; if i < tokens.count - 1 { i += 1 }; return t
    }
    private mutating func match(_ kind: ScriptToken.Kind) -> Bool {
        if peek.kind == kind { advance(); return true }
        return false
    }
    private mutating func expect(_ kind: ScriptToken.Kind, _ what: String) throws {
        guard match(kind) else { throw ScriptError.parse("expected \(what)", at: peek.at) }
    }
    private mutating func skipNewlines() { while peek.kind == .newline { advance() } }

    // MARK: - Expression grammar (lowest → highest precedence)

    private mutating func expression() throws -> ScriptNode { try ternary() }

    private mutating func ternary() throws -> ScriptNode {
        let cond = try or()
        guard match(.question) else { return cond }
        let then = try expression()
        try expect(.colon, "':' in ternary")
        let els = try expression()
        return .ternary(cond, then, els)
    }

    private mutating func or() throws -> ScriptNode {
        var left = try and()
        while match(.orOr) { left = .binary("||", left, try and()) }
        return left
    }

    private mutating func and() throws -> ScriptNode {
        var left = try comparison()
        while match(.andAnd) { left = .binary("&&", left, try comparison()) }
        return left
    }

    private mutating func comparison() throws -> ScriptNode {
        var left = try additive()
        while let op = comparisonOperator() {
            advance()
            left = .binary(op, left, try additive())
        }
        return left
    }

    /// Returns the operator string if the current token is a comparison op
    /// (symbol or the word operators matches/in/contains), else nil.
    private func comparisonOperator() -> String? {
        switch peek.kind {
        case .eq: return "=="
        case .neq: return "!="
        case .lt: return "<"
        case .lte: return "<="
        case .gt: return ">"
        case .gte: return ">="
        case .ident(let w) where w == "matches" || w == "in" || w == "contains": return w
        default: return nil
        }
    }

    private mutating func additive() throws -> ScriptNode {
        var left = try multiplicative()
        while true {
            if match(.plus) { left = .binary("+", left, try multiplicative()) }
            else if match(.minus) { left = .binary("-", left, try multiplicative()) }
            else { return left }
        }
    }

    private mutating func multiplicative() throws -> ScriptNode {
        var left = try unary()
        while true {
            if match(.star) { left = .binary("*", left, try unary()) }
            else if match(.slash) { left = .binary("/", left, try unary()) }
            else if match(.percent) { left = .binary("%", left, try unary()) }
            else { return left }
        }
    }

    private mutating func unary() throws -> ScriptNode {
        if match(.bang) { return .unary("!", try unary()) }
        if match(.minus) { return .unary("-", try unary()) }
        return try postfix()
    }

    /// Postfix chains. A leading `.` or `@` implies the implicit identity (the
    /// current query element), so `.text` is `member(identity, "text")`.
    private mutating func postfix() throws -> ScriptNode {
        var node: ScriptNode
        if peek.kind == .dot {
            // Leading dot is the implicit identity. `.field` keeps the dot for
            // the loop (member access on identity); `.`, `.@attr`, `.[i]`
            // consume the dot here as the bare identity sigil.
            if case .ident? = peek2() {
                node = .identity
            } else {
                advance()
                node = .identity
            }
        } else if peek.kind == .at {
            node = .identity
        } else {
            node = try primary()
        }
        loop: while true {
            switch peek.kind {
            case .dot:
                advance()
                guard case .ident(let name) = peek.kind else {
                    throw ScriptError.parse("expected a field name after '.'", at: peek.at)
                }
                advance()
                if match(.lparen) {
                    let args = try arguments()
                    try expect(.rparen, "')'")
                    node = .method(node, name, args)
                } else {
                    node = .member(node, name)
                }
            case .at:
                advance()
                guard case .ident(let key) = peek.kind else {
                    throw ScriptError.parse("expected an attribute name after '@'", at: peek.at)
                }
                advance()
                node = .attribute(node, key)
            case .lbracket:
                advance()
                let idx = try expression()
                try expect(.rbracket, "']'")
                node = .index(node, idx)
            default:
                break loop
            }
        }
        return node
    }

    private mutating func primary() throws -> ScriptNode {
        let tok = peek
        switch tok.kind {
        case .number(let n): advance(); return .number(n)
        case .string(let s): advance(); return .string(s)
        case .variable(let v): advance(); return .variable(v)
        case .ident(let name):
            advance()
            switch name {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "null": return .null
            default:
                if match(.lparen) {
                    let args = try arguments()
                    try expect(.rparen, "')'")
                    return .call(callee: name, args: args)
                }
                return .identifier(name)
            }
        case .lparen:
            advance()
            let e = try expression()
            try expect(.rparen, "')'")
            return e
        case .lbracket:
            return try listLiteral()
        case .lbrace:
            return try objectLiteral()
        default:
            throw ScriptError.parse("unexpected token in expression", at: tok.at)
        }
    }

    private mutating func arguments() throws -> [ScriptNode] {
        var args: [ScriptNode] = []
        if peek.kind == .rparen { return args }
        repeat { args.append(try expression()) } while match(.comma)
        return args
    }

    private mutating func listLiteral() throws -> ScriptNode {
        try expect(.lbracket, "'['")
        var items: [ScriptNode] = []
        if peek.kind != .rbracket {
            repeat { items.append(try expression()) } while match(.comma)
        }
        try expect(.rbracket, "']'")
        return .list(items)
    }

    private mutating func objectLiteral() throws -> ScriptNode {
        try expect(.lbrace, "'{'")
        var entries: [ScriptNode.ObjectEntry] = []
        if peek.kind != .rbrace {
            repeat {
                let key: String
                switch peek.kind {
                case .ident(let k): key = k; advance()
                case .string(let k): key = k; advance()
                default: throw ScriptError.parse("expected an object key", at: peek.at)
                }
                try expect(.colon, "':' after object key")
                entries.append(.init(key, try expression()))
            } while match(.comma)
        }
        try expect(.rbrace, "'}'")
        return .object(entries)
    }
}
