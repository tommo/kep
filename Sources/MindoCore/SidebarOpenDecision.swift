import Foundation

/// Decides whether a sidebar selection change should open a document.
///
/// The sidebar opens files on selection (single-click, like Obsidian's file
/// explorer), but the raw "selection changed → open" wiring had two
/// problems this gates against:
///
/// 1. **Redundant re-opens.** Selecting the file that's already the active
///    document (e.g. via the reverse sync that highlights the active doc in
///    the tree) re-ran the open path, which could reset scroll/undo focus
///    and risked an open→select→open feedback loop.
/// 2. **Folders / workspaces.** Only file nodes are documents; expanding a
///    folder must never trigger an open.
///
/// Pure so the rule is unit-testable without any SwiftUI/AppKit state.
public enum SidebarOpenDecision {
    /// `true` when selecting `node` should open it as a document.
    /// - Parameters:
    ///   - isFile: whether the selected node is a file (vs folder/workspace).
    ///   - selectedURL: the selected node's URL.
    ///   - activeURL: the currently active document's URL, if any.
    public static func shouldOpen(isFile: Bool, selectedURL: URL?, activeURL: URL?) -> Bool {
        guard isFile, let selectedURL else { return false }
        // Already showing this file — don't re-open.
        if let activeURL, activeURL.standardizedFileURL == selectedURL.standardizedFileURL {
            return false
        }
        return true
    }
}
