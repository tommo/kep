import AppKit
import MindoModel

/// Topic-tree search for the mindmap editor's in-document Find bar.
/// Returns matches in pre-order (root, then each subtree depth-first) so
/// "next match" walks predictably from top to bottom.
extension MindMapView {

    /// Match every topic whose text contains `query`. Empty / whitespace
    /// queries return no matches.
    public func findMatches(query: String, caseSensitive: Bool = false) -> [MindMapElement] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let root = rootElement else { return [] }
        let needle = caseSensitive ? trimmed : trimmed.lowercased()
        var results: [MindMapElement] = []
        root.traverse { el in
            let haystack = caseSensitive ? el.topic.text : el.topic.text.lowercased()
            if haystack.contains(needle) { results.append(el) }
        }
        return results
    }

    /// Replace every occurrence of `query` in topic titles with `replacement`.
    /// Returns the number of replacements (one per matched topic — multiple
    /// occurrences within a single title all swap in one go). Each topic
    /// edit is undoable individually.
    @discardableResult
    public func replaceAll(query: String, with replacement: String, caseSensitive: Bool = false) -> Int {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        let matches = findMatches(query: trimmed, caseSensitive: caseSensitive)
        var count = 0
        for el in matches {
            let opts: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            let next = (el.topic.text as NSString).replacingOccurrences(
                of: trimmed,
                with: replacement,
                options: opts,
                range: NSRange(location: 0, length: (el.topic.text as NSString).length)
            )
            if next != el.topic.text {
                undoableSetText(el.topic, to: next)
                count += 1
            }
        }
        return count
    }
}
