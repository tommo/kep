import AppKit
import MindoModel

/// Visual element that wraps a `Topic` for layout & rendering. Mirrors `BaseElement`
/// from `mindmap-panel`, simplified to one type with a `level` discriminator.
public final class MindMapElement {
    public let topic: Topic
    public let level: Int
    /// Children, in tree order. For the root, these split between `leftChildren` and `rightChildren`.
    public internal(set) var children: [MindMapElement] = []
    /// At root only — the left-side subset of children.
    public internal(set) var leftChildren: [MindMapElement] = []
    public internal(set) var rightChildren: [MindMapElement] = []

    /// `true` when this topic lives on the left half of the root.
    public internal(set) var isLeftSide: Bool = false

    /// The element's own rectangle (text bounds), in canvas coordinates.
    public internal(set) var frame: CGRect = .zero

    /// The size of just this element (text + insets), independent of children.
    public internal(set) var elementSize: CGSize = .zero

    /// Bounds of the entire subtree rooted at this element.
    public internal(set) var subtreeBounds: CGRect = .zero

    public init(topic: Topic, level: Int) {
        self.topic = topic
        self.level = level
    }

    /// Build an element tree from a topic tree.
    public static func build(from topic: Topic, level: Int = 0) -> MindMapElement {
        let element = MindMapElement(topic: topic, level: level)
        for child in topic.children {
            element.children.append(MindMapElement.build(from: child, level: level + 1))
        }
        return element
    }

    /// Pre-order traversal across the whole element tree.
    public func traverse(_ visit: (MindMapElement) -> Void) {
        visit(self)
        for c in children { c.traverse(visit) }
    }

    /// True if this topic's `collapsed` attribute is set.
    public var isCollapsed: Bool {
        topic.attribute(TopicAttribute.collapsed).flatMap(Bool.init) ?? false
    }

    /// Effective children for layout — empty when collapsed.
    public var visibleChildren: [MindMapElement] {
        isCollapsed ? [] : children
    }
}
