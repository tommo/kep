import AppKit
import KepModel

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

    /// Replace every occurrence of `query` in `element`'s text with
    /// `replacement` and return whether anything changed. Single-step
    /// undoable. Used by the find bar's per-match Replace button so the
    /// user can review each substitution before committing the rest.
    /// Mindolph parity: their replace bar offers both Replace and
    /// Replace All; ours used to skip straight to the bulk operation.
    @discardableResult
    public func replaceCurrent(_ element: MindMapElement, query: String, with replacement: String, caseSensitive: Bool = false) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let opts: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        let next = (element.topic.text as NSString).replacingOccurrences(
            of: trimmed,
            with: replacement,
            options: opts,
            range: NSRange(location: 0, length: (element.topic.text as NSString).length)
        )
        guard next != element.topic.text else { return false }
        undoableSetText(element.topic, to: next)
        return true
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
