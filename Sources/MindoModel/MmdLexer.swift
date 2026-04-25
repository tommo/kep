import Foundation

/// Token types produced by `MmdLexer`. Mirrors `MindMapLexer.TokenType` from the Java original.
public enum MmdTokenType {
    case headLine
    case headDelimiter
    case attribute
    case topicLevel
    case topicTitle
    case codeSnippetStart
    case codeSnippetBody
    case codeSnippetEnd
    case extraType
    case extraText
    case whitespace
    case unknownLine
}

/// Streaming lexer for `.mmd` mind-map files. Faithful port of `MindMapLexer.java`.
///
/// Usage mirrors the Java API: construct with the full text, repeatedly call `advance()`
/// and inspect `tokenType` / `tokenText`.
public struct MmdLexer {
    private let chars: [Character]
    private(set) var offset: Int
    private var endOffset: Int
    /// Internal lexer state — drives what the next `advance()` call expects.
    private var state: MmdTokenType
    /// What the most recent `advance()` reports. Diverges from `state` when we
    /// reclassify a token at the end of `advance()` (e.g. HEAD_LINE → ATTRIBUTE).
    private var reportedType: MmdTokenType
    private var tokenCompleted: Bool

    private(set) var tokenStart: Int = 0
    private(set) var tokenEnd: Int = 0

    /// Type of the most recently completed token. `nil` when no token is available.
    public var tokenType: MmdTokenType? {
        return tokenStart == tokenEnd ? nil : reportedType
    }

    public var tokenText: String {
        guard tokenStart < tokenEnd else { return "" }
        return String(chars[tokenStart..<tokenEnd])
    }

    public init(buffer: String, initialState: MmdTokenType = .headLine) {
        self.chars = Array(buffer)
        self.offset = 0
        self.endOffset = chars.count
        self.state = initialState
        self.reportedType = initialState
        self.tokenCompleted = true
    }

    private var isBufferEnd: Bool { offset >= endOffset }

    private mutating func readChar() -> Character {
        let c = chars[offset]
        offset += 1
        return c
    }

    private mutating func back() { if offset > 0 { offset -= 1 } }

    private var tokenLength: Int { offset - tokenStart }
    private var isEmptyToken: Bool { offset == tokenStart }

    public mutating func advance() {
        let resumingToken = tokenCompleted
        if resumingToken { tokenStart = offset }
        var inAction = true

        while inAction && !isBufferEnd {
            switch state {
            case .headLine:
                tokenCompleted = skipToNextLine()
                if tokenCompleted, isAllLineFromChars("-") {
                    state = .headDelimiter
                }
                inAction = false

            case .headDelimiter:
                state = .whitespace

            case .codeSnippetEnd, .whitespace:
                skipAllWhitespaceAndSpecial()
                if offset > tokenStart || isBufferEnd {
                    tokenCompleted = true
                    inAction = false
                } else {
                    let chr = readChar()
                    switch chr {
                    case "#":
                        state = .topicLevel
                    case "-", ">":
                        if isBufferEnd {
                            state = (chr == ">") ? .attribute : .extraType
                            tokenCompleted = false
                            inAction = false
                        } else {
                            let next = readChar()
                            if next == " " {
                                state = (chr == ">") ? .attribute : .extraType
                            } else {
                                state = .unknownLine
                            }
                        }
                    case "<":
                        tokenCompleted = false
                        state = .extraText
                    default:
                        state = .unknownLine
                    }
                }

            case .extraText:
                if tokenLength <= 5 && !tokenMayStartWith("<pre>") {
                    state = .unknownLine
                } else if !isBufferEnd, readChar() == ">", tokenLength > 5 {
                    if prevTextInBufferIs("</pre>") {
                        tokenCompleted = true
                        inAction = false
                    }
                }

            case .codeSnippetStart:
                tokenCompleted = toStartPositionOfCodeSnippetEnd()
                if isEmptyToken {
                    state = .codeSnippetEnd
                } else {
                    state = .codeSnippetBody
                    inAction = false
                }

            case .attribute, .extraType:
                if !isBufferEnd {
                    if tokenLength == 1 {
                        let c = readChar()
                        if c != " " {
                            state = .unknownLine
                            continue
                        }
                    }
                    tokenCompleted = skipToNextLine()
                    inAction = false
                }

            case .topicLevel:
                if !isBufferEnd {
                    let ch = readChar()
                    if ch == "#" {
                        continue
                    } else if !ch.isWhitespace {
                        back()
                    }
                    tokenCompleted = true
                    inAction = false
                }

            case .topicTitle, .unknownLine:
                tokenCompleted = skipToNextLine()
                inAction = false

            default:
                fatalError("Unexpected lexer state \(state)")
            }
        }

        // The reported type defaults to whatever state we ended in. Some cases
        // below override it without changing the internal `state`, mirroring the
        // Java separation between `tokenType` (report) and `position.state` (next).
        reportedType = state
        tokenEnd = offset

        if tokenCompleted {
            switch reportedType {
            case .headLine:
                if hasText("> ", at: tokenStart) {
                    reportedType = .attribute
                }
            case .topicLevel:
                state = .topicTitle
            case .unknownLine:
                if tokenStartsWith("```") {
                    if isAllLineFromChars("`") {
                        reportedType = .codeSnippetEnd
                        state = .codeSnippetEnd
                    } else {
                        reportedType = .codeSnippetStart
                        state = .codeSnippetStart
                    }
                }
            default:
                state = .whitespace
            }
        }
    }

    // MARK: - Helpers (mirror Java implementation)

    private func isAllLineFromChars(_ c: Character) -> Bool {
        var detected = false
        let prelimit = offset - 1
        for i in tokenStart..<offset {
            let ch = chars[i]
            if ch == "\r" || (ch == "\n" && i == prelimit) { continue }
            if ch != c { return false }
            detected = true
        }
        return detected
    }

    private mutating func skipAllWhitespaceAndSpecial() {
        while !isBufferEnd {
            let ch = readChar()
            if !(ch.isWhitespace || ch.isISOControl) {
                back()
                break
            }
        }
    }

    private mutating func skipToNextLine() -> Bool {
        var result = false
        while !isBufferEnd {
            if readChar() == "\n" { result = true; break }
        }
        return offset == chars.count || result
    }

    private func tokenStartsWith(_ s: String) -> Bool {
        let needle = Array(s)
        guard offset - tokenStart >= needle.count else { return false }
        for (i, c) in needle.enumerated() where chars[tokenStart + i] != c {
            return false
        }
        return true
    }

    private func tokenMayStartWith(_ s: String) -> Bool {
        let needle = Array(s)
        var idx = 0
        var i = tokenStart
        while i <= offset && idx < needle.count {
            if i >= chars.count || chars[i] != needle[idx] { return false }
            i += 1; idx += 1
        }
        return true
    }

    private func prevTextInBufferIs(_ s: String) -> Bool {
        let needle = Array(s)
        let start = offset - needle.count
        guard start >= 0 else { return false }
        for (i, c) in needle.enumerated() where chars[start + i] != c {
            return false
        }
        return true
    }

    private func hasText(_ s: String, at position: Int) -> Bool {
        let needle = Array(s)
        guard position >= 0, position + needle.count <= chars.count else { return false }
        for (i, c) in needle.enumerated() where chars[position + i] != c {
            return false
        }
        return true
    }

    private mutating func toStartPositionOfCodeSnippetEnd() -> Bool {
        var found = false
        var lineStart = isLineStart()
        var lineStartPosition = lineStart ? offset : -1
        var startingBacktickCount = 0
        var detectedSpaces = 0

        while !found && !isBufferEnd {
            let ch = readChar()
            switch ch {
            case "`":
                if detectedSpaces == 0 && (startingBacktickCount > 0 || lineStart) {
                    startingBacktickCount += 1
                } else {
                    startingBacktickCount = 0
                }
                lineStart = false
            case "\n":
                if startingBacktickCount == 3 {
                    found = true
                } else {
                    lineStartPosition = offset
                    startingBacktickCount = 0
                }
                lineStart = true
                detectedSpaces = 0
            default:
                if ch.isWhitespace {
                    detectedSpaces += 1
                } else if !ch.isISOControl {
                    startingBacktickCount = 0
                }
                lineStart = false
            }
        }

        if found || startingBacktickCount == 3 {
            found = true
            offset = lineStartPosition
        }
        return found
    }

    private func isLineStart() -> Bool {
        let prev = offset - 1
        if prev < 0 { return true }
        return chars[prev] == "\n"
    }
}

private extension Character {
    /// Java's `Character.isISOControl`: U+0000–U+001F or U+007F–U+009F.
    var isISOControl: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        let v = scalar.value
        return v <= 0x1F || (v >= 0x7F && v <= 0x9F)
    }
}
