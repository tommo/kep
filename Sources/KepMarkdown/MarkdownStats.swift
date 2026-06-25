import Foundation

/// Pure-logic word + character counter for the markdown editor footer.
/// Lives outside the SwiftUI bridge so the rule can be unit-tested
/// without standing up an NSTextView.
public enum MarkdownStats {

    public struct Counts: Equatable {
        public let words: Int
        public let characters: Int
        public init(words: Int, characters: Int) {
            self.words = words
            self.characters = characters
        }
    }

    /// Words = whitespace-separated runs of non-whitespace. Characters
    /// = grapheme-cluster count (so emoji and combining marks each count
    /// as one — matches what a user sees on screen).
    public static func compute(_ text: String) -> Counts {
        let words = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
        return Counts(words: words, characters: text.count)
    }
}
