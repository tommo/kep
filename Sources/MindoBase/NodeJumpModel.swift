import Foundation
import MindoCore

/// Headless logic for the Go to Node palette — a direct mirror of
/// `QuickSwitcherModel` (the proven ⌘O switcher), so the view can be a faithful
/// clone of the working `QuickSwitcherView`. Ranks `OutlineItem`s by TITLE via
/// the unit-tested `NodeJumpSearch`. The view owns one in `@State` and forwards
/// keystrokes; it then renders `results` + `selection`.
public final class NodeJumpModel {
    public let items: [OutlineItem]
    public let maxVisible: Int

    public private(set) var query: String = ""
    public private(set) var selection: Int = 0

    public init(items: [OutlineItem], maxVisible: Int = 100) {
        self.items = items
        self.maxVisible = maxVisible
    }

    public var results: [(item: OutlineItem, result: FuzzyMatch.Result)] {
        NodeJumpSearch.results(items, query: query, limit: maxVisible)
    }

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
