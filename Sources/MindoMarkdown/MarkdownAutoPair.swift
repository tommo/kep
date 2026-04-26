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
    static let pairs: [Character: Character] = [
        "(": ")",
        "[": "]",
        "{": "}",
        "\"": "\"",
        "'": "'",
        "`": "`",
    ]

    /// Closer for `opener` if the input is exactly one recognized opener.
    /// Returns nil when the input is empty, multi-character, or not an
    /// auto-pair trigger.
    public static func closer(for opener: String) -> Character? {
        guard opener.count == 1, let ch = opener.first else { return nil }
        return pairs[ch]
    }
}
