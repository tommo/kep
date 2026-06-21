import Foundation

/// A tiny query language over a topic's text + typed properties — the first
/// increment of property queries (#203 / roadmap T4). Pure → unit-testable.
///
/// Space-separated terms are ANDed; an uppercase `OR` token splits the query
/// into OR-groups (a topic matches if ANY group's terms all match). Each term:
///   • `key:value`  — the typed property `key` matches `value` (a tags/list
///     property matches if it contains `value`; others by canonical-string or
///     inferred-value equality, case-insensitive). `key:` (empty value) matches
///     any topic that HAS the property.
///   • `#tag`       — shorthand: the topic's `tags` contains `tag` (case-insensitive).
///   • `/regex/`    — the topic's text matches the regular expression.
///   • `word`       — the topic's text contains `word` (case-insensitive).
///   • a leading `-` negates any term (e.g. `-done:true`, `-#archived`).
public enum TopicQuery {

    /// True if `topic` matches the query: ANY OR-group whose every term matches.
    /// An all-whitespace query matches nothing (callers treat empty as "no filter").
    public static func matches(_ query: String, topic: Topic) -> Bool {
        let groups = orGroups(query)
        guard !groups.isEmpty else { return false }
        return groups.contains { group in
            !group.isEmpty && group.allSatisfy { evalTerm($0, topic) }
        }
    }

    /// Split a query into OR-groups of AND-terms on the uppercase `OR` token.
    static func orGroups(_ query: String) -> [[String]] {
        var groups: [[String]] = []
        var current: [String] = []
        for token in query.split(whereSeparator: { $0 == " " }).map(String.init) {
            if token == "OR" { groups.append(current); current = [] }
            else { current.append(token) }
        }
        groups.append(current)
        return groups.filter { !$0.isEmpty }
    }

    /// Evaluate a term, honoring a leading `-` negation.
    static func evalTerm(_ term: String, _ topic: Topic) -> Bool {
        if term.hasPrefix("-"), term.count > 1 {
            return !base(term: String(term.dropFirst()), matches: topic)
        }
        return base(term: term, matches: topic)
    }

    static func base(term: String, matches topic: Topic) -> Bool {
        if term.count >= 2, term.hasPrefix("/"), term.hasSuffix("/") {
            let pattern = String(term.dropFirst().dropLast())
            guard !pattern.isEmpty,
                  let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
            let range = NSRange(topic.text.startIndex..., in: topic.text)
            return re.firstMatch(in: topic.text, range: range) != nil
        }
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
