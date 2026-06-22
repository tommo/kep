import Foundation

/// A structural outline move: reorder among siblings or change depth. Pure
/// model vocabulary (the UI's `OutlineMove` maps onto this), so the index math
/// is testable without a view. See the two-way outliner (roadmap T2 #201).
public enum TopicMove {
    case up, down, indent, outdent
}

public extension Topic {
    /// Resolve a move into the `(newParent, index)` pair to hand `reparent` —
    /// the index is computed against the tree *as it is now* (before the move),
    /// matching `MindMapView.undoableReparent`'s remove-then-append-then-move.
    /// Returns nil when the move is impossible (root, no prior sibling, top-level
    /// can't outdent past the root).
    func movePlan(_ move: TopicMove) -> (newParent: Topic, index: Int)? {
        guard let parent, let i = parent.children.firstIndex(where: { $0 === self }) else { return nil }
        switch move {
        case .up:
            guard i > 0 else { return nil }
            return (parent, i - 1)
        case .down:
            guard i < parent.children.count - 1 else { return nil }
            return (parent, i + 1)
        case .indent:
            guard i > 0 else { return nil }          // becomes the last child of the previous sibling
            let newParent = parent.children[i - 1]
            return (newParent, newParent.children.count)
        case .outdent:
            guard let grand = parent.parent,
                  let pIndex = grand.children.firstIndex(where: { $0 === parent }) else { return nil }
            return (grand, pIndex + 1)               // becomes the parent's next sibling
        }
    }
}
