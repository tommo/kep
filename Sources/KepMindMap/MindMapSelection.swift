import KepModel

/// Pure selection-set reductions for multi-topic operations (copy / cut /
/// delete). Kept table-free so the descendant-pruning rule — the bit that's
/// easy to get subtly wrong — is unit-testable on plain `Topic` trees.
public enum MindMapSelection {

    /// Drop any topic that is a descendant of another topic in the set, so an
    /// operation doesn't act on a node twice (once on its own, once via an
    /// ancestor's subtree). Mirrors javamind's
    /// `TopicUtils.removeDuplicatedAndDescendants`. Input order is preserved.
    public static func topLevel(_ topics: [Topic]) -> [Topic] {
        let ids = Set(topics.map(ObjectIdentifier.init))
        return topics.filter { topic in
            var ancestor = topic.parent
            while let cur = ancestor {
                if ids.contains(ObjectIdentifier(cur)) { return false }
                ancestor = cur.parent
            }
            return true
        }
    }

    /// The subset of `topics` that may legally be reparented under
    /// `newParent` in a multi-select drag-drop. Starts from `topLevel`, then
    /// drops:
    /// - any topic already a direct child of `newParent` (a no-op move), and
    /// - any topic that is `newParent` itself or an ancestor of it (moving it
    ///   under `newParent` would create a cycle).
    public static func reparentable(_ topics: [Topic], under newParent: Topic) -> [Topic] {
        topLevel(topics).filter { topic in
            if topic.parent === newParent { return false }
            // Reject when newParent is the topic or sits inside topic's subtree.
            var t: Topic? = newParent
            while let cur = t {
                if cur === topic { return false }
                t = cur.parent
            }
            return true
        }
    }
}
