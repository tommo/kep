import KepModel

/// Pure planner for keyboard topic moves (⌘ + arrow keys). Given the
/// selected topic and a direction, it computes the destination as a
/// `(parent, index)` pair suitable for `undoableReparent(_:to:at:)` — or
/// nil when the move is impossible (at a boundary, or the topic is the
/// root). Kept free of any view/AppKit state so the index arithmetic —
/// where the off-by-one bugs live — is unit-testable on plain `Topic` trees.
///
/// Semantics mirror an outline editor (Obsidian / Workflowy), adapted to a
/// mind map:
/// - **up / down**: reorder among current siblings.
/// - **right**: indent — become the last child of the preceding sibling.
/// - **left**: outdent — become a sibling of the parent, just after it.
///
/// The returned `index` is the *final* index within the destination's
/// children (matching `undoableReparent`, which appends then moves), so the
/// caller can hand it straight through.
enum MindMapTopicMove {

    struct Plan {
        let parent: Topic
        let index: Int
        init(parent: Topic, index: Int) {
            self.parent = parent
            self.index = index
        }
    }

    static func plan(for topic: Topic, direction: MindMapView.Direction) -> Plan? {
        guard let parent = topic.parent else { return nil }   // root can't move
        let siblings = parent.children
        guard let i = siblings.firstIndex(where: { $0 === topic }) else { return nil }

        switch direction {
        case .up:
            guard i > 0 else { return nil }
            return Plan(parent: parent, index: i - 1)

        case .down:
            guard i < siblings.count - 1 else { return nil }
            return Plan(parent: parent, index: i + 1)

        case .right:
            // Indent under the preceding sibling, appended to its children.
            guard i > 0 else { return nil }
            let newParent = siblings[i - 1]
            return Plan(parent: newParent, index: newParent.children.count)

        case .left:
            // Outdent: insert into the grandparent right after the old parent.
            guard let grandparent = parent.parent else { return nil }
            guard let pIndex = grandparent.children.firstIndex(where: { $0 === parent }) else { return nil }
            return Plan(parent: grandparent, index: pIndex + 1)
        }
    }
}
