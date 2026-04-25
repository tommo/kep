import Foundation
import MindoBase
import MindoModel

public extension Outline {
    /// Walk a topic tree pre-order and produce one `OutlineItem` per topic.
    /// Target is the topic's index path inside the tree (slash-joined integers
    /// — `""` for the root, `"0"` for its first child, `"0/2"` for the third
    /// grandchild of the first child). MindMapView resolves these paths back
    /// to topics in `navigate(to:)`.
    static func fromMindMap(_ map: MindMap) -> [OutlineItem] {
        var items: [OutlineItem] = []
        guard let root = map.root else { return [] }
        walk(root, depth: 1, path: "", into: &items)
        return items
    }

    private static func walk(_ topic: Topic, depth: Int, path: String, into items: inout [OutlineItem]) {
        let title = topic.text.isEmpty ? "(untitled)" : topic.text
        items.append(OutlineItem(title: title, depth: depth, target: path))
        for (index, child) in topic.children.enumerated() {
            let childPath = path.isEmpty ? "\(index)" : "\(path)/\(index)"
            walk(child, depth: depth + 1, path: childPath, into: &items)
        }
    }
}
