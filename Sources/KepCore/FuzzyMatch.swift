import Foundation

/// Subsequence fuzzy matcher — the scoring core behind an Obsidian-style
/// quick switcher (⌘O). Given a typed query and a candidate string it
/// decides whether the query characters appear, in order, somewhere in the
/// candidate (case-insensitive), and scores the match so the best
/// candidates float to the top of a picker.
///
/// The matcher is deliberately pure and deterministic so it can be unit
/// tested without any UI: same inputs → same score and same matched
/// character indices (handy for bolding the hit in a list row).
///
/// Scoring mirrors the well-known Sublime/VS Code heuristic: reward
/// matches that land at the very start, on a word boundary (after a
/// separator, or a camelCase hump), and runs of consecutive characters;
/// gently penalise leading gaps so `cfg` prefers `config.swift` over a
/// file that merely contains those letters scattered late.
public enum FuzzyMatch {
    public struct Result: Equatable, Sendable {
        /// Higher is better. Only meaningful relative to other results for
        /// the *same* query — not an absolute quality measure.
        public let score: Int
        /// Indices into the candidate (by Character offset) that the query
        /// matched, in ascending order. Empty for an empty query.
        public let matchedIndices: [Int]

        public init(score: Int, matchedIndices: [Int]) {
            self.score = score
            self.matchedIndices = matchedIndices
        }
    }

    // Bonus / penalty weights. Tuned for short file-name candidates.
    private static let consecutiveBonus = 15
    private static let startBonus = 12
    private static let separatorBonus = 10
    private static let camelBonus = 10
    private static let leadingGapPenalty = -3   // per skipped char before first match, capped
    private static let maxLeadingGapPenalty = -9
    private static let gapPenalty = -1          // per skipped char between matches

    private static let separators = Set<Character>(["/", "\\", " ", "_", "-", ".", "(", "["])

    /// Match `query` against `candidate`. Returns `nil` when the query is
    /// not a subsequence of the candidate. An empty query is a trivial
    /// match (`score 0`, no indices) so a picker can show every item
    /// before the user types anything.
    public static func match(query: String, candidate: String) -> Result? {
        let q = Array(query.lowercased())
        guard !q.isEmpty else { return Result(score: 0, matchedIndices: []) }

        let original = Array(candidate)
        let lower = Array(candidate.lowercased())
        guard q.count <= lower.count else { return nil }

        var indices: [Int] = []
        indices.reserveCapacity(q.count)
        var qi = 0
        var ci = 0
        // Two-pointer greedy: finds a subsequence iff one exists.
        while qi < q.count && ci < lower.count {
            if q[qi] == lower[ci] {
                indices.append(ci)
                qi += 1
            }
            ci += 1
        }
        guard qi == q.count else { return nil }

        var score = 0
        var previous = -2
        for (matchPos, idx) in indices.enumerated() {
            if matchPos == 0 {
                // Leading gap before the first matched character.
                score += max(maxLeadingGapPenalty, leadingGapPenalty * idx)
                if idx == 0 { score += startBonus }
            } else {
                let gap = idx - previous - 1
                if gap == 0 {
                    score += consecutiveBonus
                } else {
                    score += gapPenalty * gap
                }
            }
            // Word-boundary bonuses apply regardless of position.
            if idx > 0 {
                let prevChar = original[idx - 1]
                if separators.contains(prevChar) {
                    score += separatorBonus
                } else if prevChar.isLowercase && original[idx].isUppercase {
                    score += camelBonus
                }
            }
            previous = idx
        }
        return Result(score: score, matchedIndices: indices)
    }

    /// Rank `items` by how well their `key` matches `query`, best first.
    /// Non-matching items are dropped. An empty query keeps every item in
    /// its original order (stable). Ties (equal score) preserve the input
    /// order so the caller can pre-sort by recency / name.
    public static func rank<T>(_ items: [T], query: String, key: (T) -> String) -> [(item: T, result: Result)] {
        if query.isEmpty {
            return items.map { ($0, Result(score: 0, matchedIndices: [])) }
        }
        let scored = items.enumerated().compactMap { offset, item -> (offset: Int, item: T, result: Result)? in
            guard let result = match(query: query, candidate: key(item)) else { return nil }
            return (offset, item, result)
        }
        return scored
            .sorted { a, b in
                if a.result.score != b.result.score { return a.result.score > b.result.score }
                return a.offset < b.offset
            }
            .map { ($0.item, $0.result) }
    }
}
