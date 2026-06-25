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
        // For numeric markers, increment; bullets mirror; task checkboxes
        // continue as a FRESH unchecked box (never carry the prior tick).
        let nextMarker: String
        switch marker.kind {
        case .bullet(let ch):
            nextMarker = "\(ch) "
        case .checkbox(let ch):
            nextMarker = "\(ch) [ ] "
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
            /// A task checkbox bullet — "- [ ] " / "* [x] ". The Character is
            /// the underlying bullet so continuation keeps the same one.
            case checkbox(Character)
            case numeric(Int)
        }
        public let kind: Kind
        public let length: Int
    }

    /// Leading whitespace (spaces or tabs) on `line`. Used as the fall-
    /// through behaviour for `insertNewline` when no list marker is
    /// present — preserves indentation on the next line.
    public static func leadingIndent(of line: String) -> String {
        return String(line.prefix(while: { $0 == " " || $0 == "\t" }))
    }

    public static func parseMarker(_ body: String) -> ParsedMarker? {
        guard let first = body.first else { return nil }
        // Bullet form: "- ", "* ", "+ " — and the task-checkbox extension
        // "- [ ] " / "- [x] " (any single state char between the brackets).
        if "-*+".contains(first), body.count >= 2, body[body.index(after: body.startIndex)] == " " {
            let chars = Array(body)
            // chars: 0=bullet 1=space 2='[' 3=state 4=']' 5=' '
            if chars.count >= 6, chars[2] == "[", chars[4] == "]", chars[5] == " " {
                return ParsedMarker(kind: .checkbox(first), length: 6)
            }
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
