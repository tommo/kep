import MindoCore

/// The actual search the "Go to Node" palette runs — extracted from the view
/// so the production code path (path key + fuzzy ranking + cap) is unit-tested
/// directly, not reimplemented in a test. The view is a thin render over this.
public enum NodeJumpSearch {
    /// What we match AND display: the breadcrumb path ending in the node title.
    /// Matching the whole path makes same-named nodes distinguishable and lets
    /// an ancestor narrow the results ("shit topic" → the Topic under shit).
    public static func pathKey(_ item: OutlineItem) -> String {
        item.breadcrumb.isEmpty ? item.title : "\(item.breadcrumb) › \(item.title)"
    }

    /// Ranked, capped matches for `query`. Empty query lists everything (so the
    /// palette shows the whole map before typing).
    public static func results(_ items: [OutlineItem], query: String,
                               limit: Int = 100) -> [(item: OutlineItem, result: FuzzyMatch.Result)] {
        Array(FuzzyMatch.rank(items, query: query) { pathKey($0) }.prefix(limit))
    }
}
