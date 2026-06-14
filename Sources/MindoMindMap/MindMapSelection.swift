import MindoModel

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
}
