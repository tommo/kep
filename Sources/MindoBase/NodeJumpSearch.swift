import MindoCore

/// The actual search the "Go to Node" palette runs — extracted from the view
/// so the production code path is unit-tested directly, not reimplemented.
public enum NodeJumpSearch {
    /// Ranked, capped matches for `query`. Matching is on the node TITLE only —
    /// NOT the ancestor path. Matching the path dragged in every descendant of
    /// any node whose name happened to contain the query (search "topic" and
    /// you'd get every child of every "Topic"). The breadcrumb is display-only,
    /// to tell same-named nodes apart. Empty query lists everything (browse).
    public static func results(_ items: [OutlineItem], query: String,
                               limit: Int = 100) -> [(item: OutlineItem, result: FuzzyMatch.Result)] {
        Array(FuzzyMatch.rank(items, query: query) { $0.title }.prefix(limit))
    }
}
