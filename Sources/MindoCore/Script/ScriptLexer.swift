import Foundation

/// One lexical token of MindoScript's expression sublanguage (the CEL-style
/// language shared by query stages, decorators, and `{{ }}` interpolation).
///
/// Words are NOT classified into keywords here — every `[A-Za-z_]…` run is an
/// `.ident`, and the parser decides contextually whether it's a source/stage
/// keyword (`nodes`, `where`, …), a word operator (`matches`/`in`/`contains`),
/// a literal (`true`/`false`/`null`), or a function name. This keeps the lexer
/// purely lexical and the reserved-word set in one place (the parser).
public struct ScriptToken: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case number(Double)
        case string(String)          // already unescaped
        case ident(String)
        case variable(String)        // `$name` → "name"
        // operators / punctuation
        case plus, minus, star, slash, percent
        case eq, neq, lt, lte, gt, gte
        case andAnd, orOr, bang
        case question, colon, assign
        case lparen, rparen, lbracket, rbracket, lbrace, rbrace
        case comma, dot, at, pipe
        case newline
        case eof
    }
    public let kind: Kind
    public let at: SourceRange
    public init(_ kind: Kind, _ at: SourceRange) {
        self.kind = kind
        self.at = at
    }
}

/// Single-pass scanner producing `[ScriptToken]` with source ranges. Skips
/// spaces/tabs and `# … ` line comments; emits one `.newline` per physical line
/// break and a trailing `.eof`. Handles double-quoted strings (with `\n \t \" \\
/// \uXXXX` escapes) and triple-quoted raw strings.
///
/// Scope (v0): the expression/query surface. The builder's RAWTEXT lines,
/// `{{ }}` extraction, and INDENT handling are the parser's line-classifier
/// phase, which re-enters this lexer on the embedded expression substrings.
public struct ScriptLexer {
    private let scalars: [Unicode.Scalar]
    private var i = 0
    private var line = 1
    private var col = 1

    public init(_ source: String) {
        self.scalars = Array(source.unicodeScalars)
    }

    public static func tokenize(_ source: String) throws -> [ScriptToken] {
        var lexer = ScriptLexer(source)
        return try lexer.run()
    }

    private var here: SourceRange { SourceRange(line: line, col: col) }
    private var atEnd: Bool { i >= scalars.count }
    private func peek(_ ahead: Int = 0) -> Unicode.Scalar? {
        let j = i + ahead
        return j < scalars.count ? scalars[j] : nil
    }

    @discardableResult
    private mutating func advance() -> Unicode.Scalar {
        let s = scalars[i]; i += 1
        if s == "\n" { line += 1; col = 1 } else { col += 1 }
        return s
    }

    private mutating func match(_ c: Unicode.Scalar) -> Bool {
        guard peek() == c else { return false }
        advance(); return true
    }

    public mutating func run() throws -> [ScriptToken] {
        var out: [ScriptToken] = []
        while !atEnd {
            let c = peek()!
            switch c {
            case " ", "\t", "\r":
                advance()
            case "\n":
                let at = here; advance(); out.append(ScriptToken(.newline, at))
            case "#":
                while let n = peek(), n != "\n" { advance() }
            case "\"":
                out.append(try scanString())
            case let d where isDigit(d):
                out.append(scanNumber())
            case let a where isIdentStart(a):
                out.append(scanIdent())
            case "$":
                out.append(try scanVariable())
            default:
                out.append(try scanSymbol())
            }
        }
        out.append(ScriptToken(.eof, here))
        return out
    }

    // MARK: - Scanners

    private func isDigit(_ s: Unicode.Scalar) -> Bool { s >= "0" && s <= "9" }
    private func isIdentStart(_ s: Unicode.Scalar) -> Bool {
        (s >= "a" && s <= "z") || (s >= "A" && s <= "Z") || s == "_"
    }
    private func isIdentCont(_ s: Unicode.Scalar) -> Bool { isIdentStart(s) || isDigit(s) }

    private mutating func scanNumber() -> ScriptToken {
        let at = here
        var text = ""
        while let n = peek(), isDigit(n) { text.unicodeScalars.append(advance()) }
        if peek() == ".", let n = peek(1), isDigit(n) {
            text.unicodeScalars.append(advance())                 // '.'
            while let n = peek(), isDigit(n) { text.unicodeScalars.append(advance()) }
        }
        if let e = peek(), e == "e" || e == "E" {
            var lookahead = 1
            if let sign = peek(1), sign == "+" || sign == "-" { lookahead = 2 }
            if let dn = peek(lookahead), isDigit(dn) {
                text.unicodeScalars.append(advance())             // 'e'
                if let sign = peek(), sign == "+" || sign == "-" { text.unicodeScalars.append(advance()) }
                while let n = peek(), isDigit(n) { text.unicodeScalars.append(advance()) }
            }
        }
        return ScriptToken(.number(Double(text) ?? 0), at)
    }

    private mutating func scanIdent() -> ScriptToken {
        let at = here
        var text = ""
        while let n = peek(), isIdentCont(n) { text.unicodeScalars.append(advance()) }
        return ScriptToken(.ident(text), at)
    }

    private mutating func scanVariable() throws -> ScriptToken {
        let at = here
        advance()                                                  // '$'
        guard let n = peek(), isIdentStart(n) else {
            throw ScriptError.lex("expected a name after '$'", line: at.line, col: at.col)
        }
        var text = ""
        while let n = peek(), isIdentCont(n) { text.unicodeScalars.append(advance()) }
        return ScriptToken(.variable(text), at)
    }

    private mutating func scanString() throws -> ScriptToken {
        let at = here
        // Triple-quoted raw string?
        if peek(1) == "\"" && peek(2) == "\"" {
            advance(); advance(); advance()                        // opening """
            var text = ""
            while !atEnd {
                if peek() == "\"" && peek(1) == "\"" && peek(2) == "\"" {
                    advance(); advance(); advance()                // closing """
                    return ScriptToken(.string(text), at)
                }
                text.unicodeScalars.append(advance())
            }
            throw ScriptError.lex("unterminated triple-quoted string", line: at.line, col: at.col)
        }
        advance()                                                  // opening "
        var text = ""
        while !atEnd {
            let c = advance()
            if c == "\"" { return ScriptToken(.string(text), at) }
            if c == "\n" { throw ScriptError.lex("unterminated string", line: at.line, col: at.col) }
            if c == "\\" {
                guard !atEnd else { throw ScriptError.lex("dangling escape in string", line: at.line, col: at.col) }
                let e = advance()
                switch e {
                case "n": text.unicodeScalars.append("\n")
                case "t": text.unicodeScalars.append("\t")
                case "\"": text.unicodeScalars.append("\"")
                case "\\": text.unicodeScalars.append("\\")
                case "u":
                    text.unicodeScalars.append(try scanUnicodeEscape(at: at))
                default:
                    throw ScriptError.lex("invalid escape \\\(e)", line: at.line, col: at.col)
                }
            } else {
                text.unicodeScalars.append(c)
            }
        }
        throw ScriptError.lex("unterminated string", line: at.line, col: at.col)
    }

    private mutating func scanUnicodeEscape(at: SourceRange) throws -> Unicode.Scalar {
        var hex = ""
        for _ in 0..<4 {
            guard let h = peek(), isHex(h) else {
                throw ScriptError.lex("\\u needs 4 hex digits", line: at.line, col: at.col)
            }
            hex.unicodeScalars.append(advance())
        }
        guard let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) else {
            throw ScriptError.lex("invalid unicode scalar \\u\(hex)", line: at.line, col: at.col)
        }
        return scalar
    }

    private func isHex(_ s: Unicode.Scalar) -> Bool {
        isDigit(s) || (s >= "a" && s <= "f") || (s >= "A" && s <= "F")
    }

    private mutating func scanSymbol() throws -> ScriptToken {
        let at = here
        let c = advance()
        let kind: ScriptToken.Kind
        switch c {
        case "+": kind = .plus
        case "-": kind = .minus
        case "*": kind = .star
        case "/": kind = .slash
        case "%": kind = .percent
        case "(": kind = .lparen
        case ")": kind = .rparen
        case "[": kind = .lbracket
        case "]": kind = .rbracket
        case "{": kind = .lbrace
        case "}": kind = .rbrace
        case ",": kind = .comma
        case ".": kind = .dot
        case "@": kind = .at
        case "|": kind = match("|") ? .orOr : .pipe
        case "&":
            guard match("&") else { throw ScriptError.lex("expected '&&'", line: at.line, col: at.col) }
            kind = .andAnd
        case "?": kind = .question
        case ":": kind = .colon
        case "=": kind = match("=") ? .eq : .assign
        case "!": kind = match("=") ? .neq : .bang
        case "<": kind = match("=") ? .lte : .lt
        case ">": kind = match("=") ? .gte : .gt
        default:
            throw ScriptError.lex("unexpected character '\(c)'", line: at.line, col: at.col)
        }
        return ScriptToken(kind, at)
    }
}
