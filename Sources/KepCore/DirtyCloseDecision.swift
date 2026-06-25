import Foundation

/// The user's answer to the "you have unsaved changes" prompt shown when a
/// dirty document (or a batch of them) is about to be closed.
public enum DirtyCloseChoice {
    /// Save the dirty document(s), then close.
    case save
    /// Close without saving — discard the unsaved changes.
    case discard
    /// Abort the close entirely; leave everything open and dirty.
    case cancel
}

/// Pure, UI-free part of the "close a dirty tab" flow (card #178). The alert
/// itself lives in `AppSession`; this decides *which* documents in a close
/// request still hold unsaved changes and therefore need a confirmation
/// prompt. Keeping it separate makes the data-loss-critical decision
/// unit-testable without standing up AppKit.
public enum DirtyCloseDecision {
    /// One closable document, reduced to just what the decision needs.
    public struct Item<ID> {
        public let id: ID
        public let isDirty: Bool
        public init(id: ID, isDirty: Bool) {
            self.id = id
            self.isDirty = isDirty
        }
    }

    /// The ids of the documents that are dirty and so must be confirmed before
    /// closing. Order is preserved so a batch prompt can list them stably.
    public static func dirtyIDs<ID>(among items: [Item<ID>]) -> [ID] {
        items.filter(\.isDirty).map(\.id)
    }

    /// Whether closing this set requires *any* prompt at all — i.e. at least
    /// one document is dirty. Lets the caller take the silent fast path when
    /// nothing would be lost.
    public static func needsPrompt<ID>(among items: [Item<ID>]) -> Bool {
        items.contains(where: \.isDirty)
    }
}
