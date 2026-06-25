import Foundation

/// A single action surfaced in the ⌘⇧P command palette. Pure data — the
/// closure that actually runs the command lives in the UI layer, keyed by
/// `id` — so ranking and selection stay unit-testable without AppKit.
public struct AppCommand: Identifiable, Equatable {
    public let id: String
    /// Human-readable command name, e.g. "Save All". This is what the
    /// fuzzy matcher ranks against.
    public let title: String
    /// Optional grouping hint shown dim on the right, e.g. "File".
    public let category: String?
    /// Optional rendered keyboard shortcut, e.g. "⌥⌘S".
    public let shortcut: String?
    /// When false the row is shown disabled and can't be invoked — mirrors
    /// the `.disabled(...)` state of the backing menu item.
    public let isEnabled: Bool

    public init(id: String, title: String, category: String? = nil,
                shortcut: String? = nil, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.category = category
        self.shortcut = shortcut
        self.isEnabled = isEnabled
    }
}

/// Headless interaction logic for the ⌘⇧P command palette, split out of the
/// SwiftUI view exactly like `QuickSwitcherModel`: typing, arrow-key
/// navigation with clamping, the visible cap, and "which command is
/// highlighted" are all unit-testable without a running UI.
///
/// Disabled commands are ranked and shown (so users see they exist) but the
/// highlight skips over them and they can't be the `selectedCommand`.
public final class CommandPaletteModel {
    public let commands: [AppCommand]
    public let maxVisible: Int

    public private(set) var query: String = ""
    public private(set) var selection: Int = 0

    public init(commands: [AppCommand], maxVisible: Int = 50) {
        self.commands = commands
        self.maxVisible = maxVisible
    }

    /// Ranked, capped results for the current query. With an empty query
    /// the catalog is returned in its declared order (FuzzyMatch passes
    /// everything through and keeps input order), which is the natural
    /// "browse all commands" view Obsidian shows on open.
    public var results: [(item: AppCommand, result: FuzzyMatch.Result)] {
        Array(FuzzyMatch.rank(commands, query: query) { $0.title }.prefix(maxVisible))
    }

    /// The highlighted command, or nil when the row is empty/disabled.
    public var selectedCommand: AppCommand? {
        let r = results
        guard r.indices.contains(selection) else { return nil }
        let cmd = r[selection].item
        return cmd.isEnabled ? cmd : nil
    }

    /// Update the query and move the highlight to the first *enabled* result.
    public func setQuery(_ newValue: String) {
        query = newValue
        selection = firstEnabledIndex(from: 0, forward: true) ?? 0
    }

    /// Move the highlight by `delta`, skipping disabled rows, clamped to the
    /// result bounds (no wrap — matches the quick switcher).
    public func move(_ delta: Int) {
        let r = results
        guard !r.isEmpty else { selection = 0; return }
        let step = delta >= 0 ? 1 : -1
        var idx = selection
        for _ in 0..<r.count {
            let next = idx + step
            guard r.indices.contains(next) else { break }
            idx = next
            if r[idx].item.isEnabled { selection = idx; return }
        }
        // No enabled row in that direction — stay put.
    }

    /// Directly select a row (mouse), clamped; ignored if that row is
    /// disabled so a click can't land the highlight on a dead command.
    public func select(at index: Int) {
        let r = results
        guard r.indices.contains(index), r[index].item.isEnabled else { return }
        selection = index
    }

    private func firstEnabledIndex(from start: Int, forward: Bool) -> Int? {
        let r = results
        guard !r.isEmpty else { return nil }
        let range = forward ? Array(start..<r.count) : Array((0...start).reversed())
        return range.first { r[$0].item.isEnabled }
    }
}
