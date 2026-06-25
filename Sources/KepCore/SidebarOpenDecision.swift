import Foundation

/// What drove a sidebar selection change — the rule treats each source
/// differently (see `SidebarOpenDecision`).
public enum SidebarSelectionSource {
    /// A mouse click on a row. Opens the file (single-click, Obsidian-style).
    case pointer
    /// Arrow-key traversal of the tree. Moves the highlight only — does NOT
    /// open, so paging through a folder no longer floods open every file it
    /// passes over.
    case keyboardNavigation
    /// An explicit Return on the selected row. Opens, like a click.
    case keyboardConfirm
}

/// Decides whether a sidebar selection change should open a document.
///
/// The sidebar opens files on selection (single-click, like Obsidian's file
/// explorer), but the raw "selection changed → open" wiring had three
/// problems this gates against:
///
/// 1. **Redundant re-opens.** Selecting the file that's already the active
///    document (e.g. via the reverse sync that highlights the active doc in
///    the tree) re-ran the open path, which could reset scroll/undo focus
///    and risked an open→select→open feedback loop.
/// 2. **Folders / workspaces.** Only file nodes are documents; expanding a
///    folder must never trigger an open.
/// 3. **Keyboard traversal floods opens.** Arrow-keying through the tree
///    changes the selection on every row, which used to open each file in
///    turn. Keyboard navigation now only highlights; Return opens.
///
/// Pure so the rule is unit-testable without any SwiftUI/AppKit state.
public enum SidebarOpenDecision {
    /// `true` when selecting `node` should open it as a document.
    /// - Parameters:
    ///   - isFile: whether the selected node is a file (vs folder/workspace).
    ///   - selectedURL: the selected node's URL.
    ///   - activeURL: the currently active document's URL, if any.
    ///   - source: what drove the selection change (defaults to `.pointer`,
    ///     the original click-to-open behaviour).
    public static func shouldOpen(
        isFile: Bool,
        selectedURL: URL?,
        activeURL: URL?,
        source: SidebarSelectionSource = .pointer
    ) -> Bool {
        // Arrow-key traversal only moves the highlight — never opens.
        if source == .keyboardNavigation { return false }
        guard isFile, let selectedURL else { return false }
        // Already showing this file — don't re-open.
        if let activeURL, activeURL.standardizedFileURL == selectedURL.standardizedFileURL {
            return false
        }
        return true
    }
}
