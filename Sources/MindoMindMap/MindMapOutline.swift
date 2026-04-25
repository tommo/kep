import Foundation
import MindoBase
import MindoModel

public extension Outline {
    /// Walk a topic tree pre-order and produce one `OutlineItem` per topic.
    /// Target is the topic's UID (when set) or its position path otherwise.
    static func fromMindMap(_ map: MindMap) -> [OutlineItem] {
        var items: [OutlineItem] = []
        guard let root = map.root else { return [] }
        walk(root, depth: 1, into: &items)
        return items
    }

    private static func walk(_ topic: Topic, depth: Int, into items: inout [OutlineItem]) {
        let title = topic.text.isEmpty ? "(untitled)" : topic.text
        let uid = topic.attribute(ExtraTopic.topicUidAttr) ?? "depth-\(depth)-\(items.count)"
        items.append(OutlineItem(title: title, depth: depth, target: uid))
        for child in topic.children {
            walk(child, depth: depth + 1, into: &items)
        }
    }
}
