import Foundation

/// Pure-logic decider for "what should Enter do on this markdown line?".
/// Lives outside the NSTextView so the per-marker rules + edge cases are
/// unit-testable without standing up an editor.
public enum MarkdownListContinuation {

    /// Action the editor should perform when the user hits Enter inside a
    /// markdown list line.
    public enum Action: Equatable {
        /// Continue the list — insert "\n" + this prefix at the caret.
        case insert(String)
        /// The current line is an empty list marker; clear it (drop the
        /// user out of the list) instead of inserting a new bullet.
        case clearMarker
    }

    /// Return the right action for `line` (the text on the current line up
    /// to the caret). `nil` means "no list marker here — fall through to
    /// the standard newline".
    public static func action(for line: String) -> Action? {
        // Split leading whitespace so nested lists keep their indent.
        let indentEnd = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = String(line.prefix(indentEnd))
        let body = String(line.dropFirst(indentEnd))
        guard let marker = parseMarker(body) else { return nil }
        let bodyAfterMarker = body.dropFirst(marker.length)
            .trimmingCharacters(in: .whitespaces)
        if bodyAfterMarker.isEmpty {
            return .clearMarker
        }
        // For numeric markers, increment; for bullets, mirror.
        let nextMarker: String
        switch marker.kind {
        case .bullet(let ch):
            nextMarker = "\(ch) "
        case .numeric(let n):
            nextMarker = "\(n + 1). "
        }
        return .insert("\(indent)\(nextMarker)")
    }

    /// Parsed list marker plus the count of leading characters it consumed
    /// from the line body (after indent). Internal helper — exposed for tests.
    public struct ParsedMarker: Equatable {
        public enum Kind: Equatable {
            case bullet(Character)
            case numeric(Int)
        }
        public let kind: Kind
        public let length: Int
    }

    public static func parseMarker(_ body: String) -> ParsedMarker? {
        guard let first = body.first else { return nil }
        // Bullet form: "- ", "* ", "+ "
        if "-*+".contains(first), body.count >= 2, body[body.index(after: body.startIndex)] == " " {
            return ParsedMarker(kind: .bullet(first), length: 2)
        }
        // Numeric form: "<digits>. "
        var idx = body.startIndex
        var digits = ""
        while idx < body.endIndex, body[idx].isASCII, body[idx].isNumber {
            digits.append(body[idx])
            idx = body.index(after: idx)
        }
        if !digits.isEmpty, idx < body.endIndex, body[idx] == ".",
           let after = body.index(idx, offsetBy: 1, limitedBy: body.endIndex),
           after < body.endIndex, body[after] == " ",
           let n = Int(digits) {
            return ParsedMarker(kind: .numeric(n), length: digits.count + 2) // digits + ". "
        }
        return nil
    }
}
