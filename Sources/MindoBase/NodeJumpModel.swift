import Foundation
import MindoCore

/// Headless logic for the "Go to Node" palette — fuzzy-search the active
/// mind map's outline (its topics) and jump to one. Mirrors
/// `QuickSwitcherModel` but ranks `OutlineItem`s by their title, so the view
/// is a thin render of `results` + `selection`. Split out so typing / arrow
/// navigation / the visible cap are unit-testable without a running UI.
public final class NodeJumpModel {
    /// All outline rows (topics) to rank against. Set once when opened.
    public let items: [OutlineItem]
    /// Max rows rendered; ranking still scans everything.
    public let maxVisible: Int

    public private(set) var query: String = ""
    public private(set) var selection: Int = 0

    public init(items: [OutlineItem], maxVisible: Int = 50) {
        self.items = items
        self.maxVisible = maxVisible
    }

    /// Ranked, capped results for the current query. With an empty query
    /// FuzzyMatch returns every item (score 0), so the full outline shows.
    public var results: [(item: OutlineItem, result: FuzzyMatch.Result)] {
        Array(FuzzyMatch.rank(items, query: query) { $0.title }.prefix(maxVisible))
    }

    /// The row under the highlight, or nil when there are no results.
    public var selectedItem: OutlineItem? {
        let r = results
        guard r.indices.contains(selection) else { return nil }
        return r[selection].item
    }

    public func setQuery(_ newValue: String) {
        query = newValue
        selection = 0
    }

    public func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { selection = 0; return }
        selection = min(max(0, selection + delta), count - 1)
    }

    public func select(at index: Int) {
        let count = results.count
        guard count > 0 else { selection = 0; return }
        selection = min(max(0, index), count - 1)
    }
}
