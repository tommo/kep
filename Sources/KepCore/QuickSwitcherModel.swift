import Foundation

/// Headless interaction logic for the ⌘O quick switcher, split out of the
/// SwiftUI view so the behaviour the user actually drives — typing,
/// arrow-key navigation, wrap/clamp at the ends, the visible-result cap,
/// and "open the highlighted file" — is unit-testable without a running UI.
///
/// The view owns one of these and forwards keystrokes to it; the view is
/// then a thin render of `results` + `selection`.
public final class QuickSwitcherModel {
    /// Full file index to rank against. Set once when the switcher opens.
    public let files: [WorkspaceFile]
    /// Max rows rendered. Ranking still scans the whole index; only the
    /// top slice is surfaced so a huge workspace stays responsive.
    public let maxVisible: Int

    public private(set) var query: String = ""
    public private(set) var selection: Int = 0

    public init(files: [WorkspaceFile], maxVisible: Int = 50) {
        self.files = files
        self.maxVisible = maxVisible
    }

    /// Ranked, capped results for the current query. Recomputed on read —
    /// the index is small enough (capped at 20k) that memoizing isn't worth
    /// the staleness risk.
    public var results: [(item: WorkspaceFile, result: FuzzyMatch.Result)] {
        Array(FuzzyMatch.rank(files, query: query) { $0.relativePath }.prefix(maxVisible))
    }

    /// The file under the highlight, or nil when there are no results.
    public var selectedFile: WorkspaceFile? {
        let r = results
        guard r.indices.contains(selection) else { return nil }
        return r[selection].item
    }

    /// Update the query. Resets the highlight to the top — after retyping,
    /// the best match is row 0 and that's what the user expects to open.
    public func setQuery(_ newValue: String) {
        query = newValue
        selection = 0
    }

    /// Move the highlight by `delta` rows, clamped to the result bounds.
    /// No wrap-around (matches Obsidian: ↓ at the last row stays put).
    public func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { selection = 0; return }
        selection = min(max(0, selection + delta), count - 1)
    }

    /// Directly select a row (mouse hover/click), clamped to valid range.
    public func select(at index: Int) {
        let count = results.count
        guard count > 0 else { selection = 0; return }
        selection = min(max(0, index), count - 1)
    }
}
