import Foundation

/// Tag queries over a mind map's typed `tags` property (the well-known list
/// property the keystone markers render). Powers the inspector's tag list +
/// "select all with this tag" filter. Pure → unit-testable. See #187 / #200.
public enum MindMapTags {

    /// Distinct tags across the whole map with how many topics carry each,
    /// sorted alphabetically. Empty tags are ignored.
    public static func tagCounts(in map: MindMap) -> [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        map.root?.traverse { topic in
            for tag in tags(of: topic) { counts[tag, default: 0] += 1 }
        }
        return counts.map { (tag: $0.key, count: $0.value) }.sorted { $0.tag < $1.tag }
    }

    /// Every topic whose `tags` list contains `tag`, in pre-order.
    public static func topicsWithTag(_ tag: String, in map: MindMap) -> [Topic] {
        var out: [Topic] = []
        map.root?.traverse { topic in
            if tags(of: topic).contains(tag) { out.append(topic) }
        }
        return out
    }

    /// The non-empty tags on a topic (its `tags` list property), or [].
    public static func tags(of topic: Topic) -> [String] {
        guard case .list(let items)? = topic.property(PropertyMarkers.tagsKey) else { return [] }
        return items.filter { !$0.isEmpty }
    }
}
