import Foundation

/// Pure reorder math shared with the tab-bar drag-and-drop delegate. Lives
/// in MindoCore so the rule (where a dragged tab lands relative to its
/// drop target) can be unit-tested without SwiftUI.
public enum TabReorder {
    /// Move `sourceID` to the slot held by `targetID`. Standard macOS
    /// reorder semantics: source ends up at target's original index, and
    /// target shifts away in the drag direction (after removal of source,
    /// inserting at the original target index has the right effect — source
    /// lands *after* target when dragging right, *at* target when dragging
    /// left). No-op when source equals target or either ID is missing.
    public static func move<ID: Equatable>(_ ids: [ID], from sourceID: ID, to targetID: ID) -> [ID] {
        guard sourceID != targetID,
              let from = ids.firstIndex(of: sourceID),
              let to = ids.firstIndex(of: targetID) else {
            return ids
        }
        var out = ids
        let item = out.remove(at: from)
        out.insert(item, at: to)
        return out
    }
}
