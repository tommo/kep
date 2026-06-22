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
        walk(root, depth: 1, path: "", ancestors: [], into: &items)
        return items
    }

    private static func walk(_ topic: Topic, depth: Int, path: String,
                             ancestors: [String], into items: inout [OutlineItem]) {
        let title = topic.text.isEmpty ? "(untitled)" : topic.text
        // Breadcrumb is the ancestor chain (NOT including this node) — lets the
        // Go to Node palette show "Root › Branch" beside an otherwise ambiguous
        // leaf and fuzzy-match across the whole path.
        let breadcrumb = ancestors.joined(separator: " › ")
        items.append(OutlineItem(title: title, depth: depth, target: path,
                                 breadcrumb: breadcrumb, markers: outlineMarkers(for: topic)))
        for (index, child) in topic.children.enumerated() {
            let childPath = path.isEmpty ? "\(index)" : "\(path)/\(index)"
            walk(child, depth: depth + 1, path: childPath,
                 ancestors: ancestors + [title], into: &items)
        }
    }

    /// Map a topic's typed-property markers (the same `PropertyMarkers.markerRow`
    /// the canvas draws) to the dependency-free `OutlineMarker` the panel renders,
    /// so the outline shows priority/done/progress/tags inline (roadmap T2 #201).
    static func outlineMarkers(for topic: Topic) -> [OutlineMarker] {
        PropertyMarkers.markerRow(for: topic).map { marker in
            let tint: OutlineMarker.Tint
            switch marker.role {
            case .priority(let p): tint = .priority(p)
            case .doneTrue:        tint = .done
            case .doneFalse:       tint = .todo
            case .progress:        tint = .accent
            case .tags:            tint = .neutral
            }
            return OutlineMarker(symbolName: marker.symbolName, tint: tint)
        }
    }
}
