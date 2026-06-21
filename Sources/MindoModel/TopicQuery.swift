import Foundation

/// A tiny query language over a topic's text + typed properties — the first
/// increment of property queries (#203 / roadmap T4). Pure → unit-testable.
///
/// A query is space-separated terms, ANDed together. Each term is one of:
///   • `key:value`  — the typed property `key` matches `value` (a tags/list
///     property matches if it contains `value`; others by canonical-string or
///     inferred-value equality, case-insensitive). `key:` (empty value) matches
///     any topic that HAS the property.
///   • `#tag`       — shorthand: the topic's `tags` contains `tag` (case-insensitive).
///   • `word`       — the topic's text contains `word` (case-insensitive).
public enum TopicQuery {

    /// True if `topic` satisfies every term in `query`. An all-whitespace query
    /// matches nothing (callers treat empty as "no filter").
    public static func matches(_ query: String, topic: Topic) -> Bool {
        let terms = query.split(whereSeparator: { $0 == " " }).map(String.init)
        guard !terms.isEmpty else { return false }
        return terms.allSatisfy { term(term: $0, matches: topic) }
    }

    static func term(term: String, matches topic: Topic) -> Bool {
        if term.hasPrefix("#") {
            let tag = String(term.dropFirst())
            return !tag.isEmpty && MindMapTags.tags(of: topic)
                .contains { $0.localizedCaseInsensitiveContains(tag) }
        }
        if let colon = term.firstIndex(of: ":") {
            let key = String(term[..<colon])
            let value = String(term[term.index(after: colon)...])
            if key.isEmpty { return topic.text.localizedCaseInsensitiveContains(term) }
            if key == "text" { return topic.text.localizedCaseInsensitiveContains(value) }
            if key == "tag" || key == "tags" {
                return value.isEmpty
                    ? !MindMapTags.tags(of: topic).isEmpty
                    : MindMapTags.tags(of: topic).contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            }
            guard let pv = topic.property(key) else { return false }
            if value.isEmpty { return true }                       // key present
            if case .list(let items) = pv {
                return items.contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            }
            return PropertyCodec.encode(pv).caseInsensitiveCompare(value) == .orderedSame
                || PropertyInference.infer(value) == pv
        }
        return topic.text.localizedCaseInsensitiveContains(term)
    }

    /// Every topic in `map` matching `query`, in pre-order.
    public static func evaluate(_ query: String, in map: MindMap) -> [Topic] {
        var out: [Topic] = []
        map.root?.traverse { if matches(query, topic: $0) { out.append($0) } }
        return out
    }
}
