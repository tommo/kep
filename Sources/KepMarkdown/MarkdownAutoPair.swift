import Foundation

/// Pure-logic lookup for the markdown editor's auto-pair behavior.
/// Lives outside the NSTextView so the per-character mapping is unit-
/// testable. Skipping `*` and `_` deliberately — bold/italic markers
/// would create wrong pairings (typing `**bold**` would expand to
/// `*` `*` `**bold**`).
public enum MarkdownAutoPair {

    /// Mapping of opener → closer. Lookup returns nil for any input that
    /// shouldn't trigger auto-pair (multi-char strings, unknown openers,
    /// the deliberately-skipped markdown emphasis chars).
    ///
    /// Backticks are intentionally absent: the auto-pair would mangle
    /// fenced code-block typing — each ` keypress would insert two ` and
    /// step the caret one forward, so "```" turns into "``````" (6
    /// backticks, caret in the middle). Single inline code is easy to
    /// close manually; fenced blocks need to type cleanly.
    static let pairs: [Character: Character] = [
        "(": ")",
        "[": "]",
        "{": "}",
        "\"": "\"",
        "'": "'",
    ]

    /// Closer for `opener` if the input is exactly one recognized opener.
    /// Returns nil when the input is empty, multi-character, or not an
    /// auto-pair trigger.
    public static func closer(for opener: String) -> Character? {
        guard opener.count == 1, let ch = opener.first else { return nil }
        return pairs[ch]
    }

    /// True when `input` is a single recognized closer character — drives
    /// the "step over the closer instead of typing it twice" behavior on
    /// the markdown editor. Mirror-pairs (`"`/`'`) are deliberately
    /// excluded from this set because the same char is both opener and
    /// closer; stepping past `"` after `""` would prevent ever typing the
    /// quoted body.
    public static func isSteppableCloser(_ input: String) -> Bool {
        guard input.count == 1, let ch = input.first else { return false }
        return ch == ")" || ch == "]" || ch == "}"
    }
}
