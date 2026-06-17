import Foundation

/// Line/indentation-based program parser — MindoScript's Phase A. Splits source
/// into top-level blocks by indentation (a column-0 line starting a block, its
/// indented lines belonging to it), then parses each: `?` query blocks via the
/// token parser, `map` builder blocks via the indentation/decorator scanner here.
public extension ScriptParser {

    static func parseProgram(_ source: String) throws -> [TopLevel] {
        let lines = splitLines(source)
        var blocks: [TopLevel] = []
        var i = 0
        while i < lines.count {
            let head = lines[i]
            guard head.depth == 0 else {
                throw ScriptError.parse("unexpected indentation at top level", at: SourceRange(line: head.line, col: 1))
            }
            var body: [PhysicalLine] = []
            var j = i + 1
            while j < lines.count, lines[j].depth > 0 { body.append(lines[j]); j += 1 }

            if head.content.hasPrefix("?") {
                let text = ([head.content] + body.map(\.content)).joined(separator: "\n")
                blocks.append(.query(try parseQuery(text)))
            } else if isMapHeader(head.content) {
                blocks.append(.map(try parseMapBlock(header: head, body: body)))
            } else {
                throw ScriptError.parse("expected a `?` query or `map` block", at: SourceRange(line: head.line, col: 1))
            }
            i = j
        }
        return blocks
    }

    // MARK: - Lines

    struct PhysicalLine: Equatable { let depth: Int; let content: String; let line: Int }

    /// Split into non-blank, non-comment lines with their 2-space indent depth.
    static func splitLines(_ source: String) -> [PhysicalLine] {
        var out: [PhysicalLine] = []
        for (idx, raw) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            var spaces = 0
            var started = false
            var content = ""
            for ch in raw {
                if !started, ch == " " { spaces += 1; continue }
                if !started, ch == "\t" { spaces += 2; continue }
                started = true
                content.append(ch)
            }
            let trimmed = content.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }   // blank / comment-only
            out.append(PhysicalLine(depth: spaces / 2, content: trimmed, line: idx + 1))
        }
        return out
    }

    private static func isMapHeader(_ content: String) -> Bool {
        content == "map" || content.hasPrefix("map ") || content.hasPrefix("map\t")
    }

    // MARK: - Map block

    static func parseMapBlock(header: PhysicalLine, body: [PhysicalLine]) throws -> MapBlock {
        let toks = try ScriptLexer.tokenize(header.content)
        guard toks.count >= 2, case .ident("map") = toks[0].kind, case .string(let name) = toks[1].kind else {
            throw ScriptError.parse("map block header must be: map \"Name\"", at: SourceRange(line: header.line, col: 1))
        }
        let lines = try body.map { line -> BuilderLine in
            let (b, decos) = try parseBuilderBody(line.content, line: line.line)
            return BuilderLine(depth: line.depth, body: b, decorators: decos)
        }
        return MapBlock(name: name, lines: lines)
    }

    /// Parse one builder line's content into a body + decorators. Splits off
    /// `| @k: expr` decorators (respecting strings and `{{ }}`), then parses the
    /// text run (literals + `{{ expr }}`) or a `from $var` clause.
    static func parseBuilderBody(_ raw: String, line: Int) throws -> (BuilderBody, [Decorator]) {
        let segments = splitTopLevelPipes(raw)
        let textPart = segments[0].trimmingCharacters(in: .whitespaces)
        let decorators = try segments.dropFirst().map { try parseDecorator($0, line: line) }

        let body: BuilderBody
        if textPart == "from" || textPart.hasPrefix("from ") {
            let rest = textPart.dropFirst(4).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("$"), rest.count > 1 else {
                throw ScriptError.parse("expected $var after 'from'", at: SourceRange(line: line, col: 1))
            }
            body = .from(String(rest.dropFirst()))
        } else {
            body = .text(try parseTextPieces(textPart, line: line))
        }
        return (body, decorators)
    }

    /// Split on `|` separators that are NOT escaped, inside a string, or inside
    /// `{{ }}`. Used to peel decorators off the text run.
    private static func splitTopLevelPipes(_ s: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        let chars = Array(s)
        var i = 0, depth = 0, inStr = false
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count { cur.append(c); cur.append(chars[i + 1]); i += 2; continue }
            if inStr {
                if c == "\"" { inStr = false }
                cur.append(c); i += 1; continue
            }
            if c == "\"" { inStr = true; cur.append(c); i += 1; continue }
            if c == "{", i + 1 < chars.count, chars[i + 1] == "{" { depth += 1; cur += "{{"; i += 2; continue }
            if c == "}", i + 1 < chars.count, chars[i + 1] == "}", depth > 0 { depth -= 1; cur += "}}"; i += 2; continue }
            if c == "|", depth == 0 { parts.append(cur); cur = ""; i += 1; continue }
            cur.append(c); i += 1
        }
        parts.append(cur)
        return parts
    }

    /// Parse a topic-text run: literal characters with `\X` escapes and
    /// `{{ expr }}` interpolations.
    private static func parseTextPieces(_ s: String, line: Int) throws -> [TextPiece] {
        var pieces: [TextPiece] = []
        var lit = ""
        let chars = Array(s)
        var i = 0
        func flush() { if !lit.isEmpty { pieces.append(.literal(lit)); lit = "" } }
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count { lit.append(chars[i + 1]); i += 2; continue }
            if c == "{", i + 1 < chars.count, chars[i + 1] == "{" {
                flush()
                var j = i + 2
                var expr = ""
                while j + 1 < chars.count, !(chars[j] == "}" && chars[j + 1] == "}") {
                    expr.append(chars[j]); j += 1
                }
                guard j + 1 < chars.count else {
                    throw ScriptError.parse("unterminated {{ … }} interpolation", at: SourceRange(line: line, col: 1))
                }
                pieces.append(.interp(try ScriptParser.parseExpression(expr)))
                i = j + 2
                continue
            }
            lit.append(c); i += 1
        }
        flush()
        return pieces
    }

    private static func parseDecorator(_ raw: String, line: Int) throws -> Decorator {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("@") else {
            throw ScriptError.parse("decorator must start with '@'", at: SourceRange(line: line, col: 1))
        }
        let afterAt = t.dropFirst()
        guard let colon = afterAt.firstIndex(of: ":") else {
            throw ScriptError.parse("decorator must be '@key: expr'", at: SourceRange(line: line, col: 1))
        }
        let key = afterAt[..<colon].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            throw ScriptError.parse("empty decorator key", at: SourceRange(line: line, col: 1))
        }
        let exprStr = String(afterAt[afterAt.index(after: colon)...])
        return Decorator(key: key, value: try ScriptParser.parseExpression(exprStr))
    }
}
