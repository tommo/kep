import Foundation
import MindoModel

// G4 — Topic extras: notes, jump-links, collapse. Implemented by the agent-tools sprint.
extension MindoAgentTools {
    static let topicExtrasDescriptors: [(name: String, description: String, parametersJSON: String)] = [
        ("set_topic_note", "Attach (or replace) a free-text note on a topic targeted by `path` (stable outline path) or `query` substring.",
         #"{"type":"object","properties":{"query":{"type":"string"},"path":{"type":"string"},"text":{"type":"string"}},"required":["text"]}"#),
        ("get_topic_note", "Read the note text attached to a topic targeted by `path` or `query`. Returns '(no note)' when none.",
         #"{"type":"object","properties":{"query":{"type":"string"},"path":{"type":"string"}}}"#),
        ("link_topics", "Add a jump-link from one topic to another. Target the source by `from_path` (stable outline path) or `from` (substring), and the destination by `to_path` or `to`.",
         #"{"type":"object","properties":{"from":{"type":"string"},"from_path":{"type":"string"},"to":{"type":"string"},"to_path":{"type":"string"}}}"#),
        ("set_topic_collapsed", "Collapse or expand a topic's subtree. Target by `path` or `query`; `collapsed` true hides children, false shows them.",
         #"{"type":"object","properties":{"query":{"type":"string"},"path":{"type":"string"},"collapsed":{"type":"boolean"}},"required":["collapsed"]}"#),
    ]

    func handleTopicExtras(_ name: String, _ a: ToolArgs) -> String? {
        switch name {
        case "set_topic_note":
            guard let text = a.str("text") else { return "error: missing 'text'" }
            guard let t = resolveTopic(a) else { return "error: no topic matches the given path/query" }
            t.setExtra(ExtraNote(text: text))
            effects.mapMutated = true
            return "set note on \"\(t.text)\""

        case "get_topic_note":
            guard let t = resolveTopic(a) else { return "error: no topic matches the given path/query" }
            return (t.extra(.note) as? ExtraNote)?.text ?? "(no note)"

        case "link_topics":
            guard let source = resolveLinkEndpoint(a, pathKey: "from_path", queryKey: "from") else {
                return "error: no topic matches the given from_path/from"
            }
            guard let target = resolveLinkEndpoint(a, pathKey: "to_path", queryKey: "to") else {
                return "error: no topic matches the given to_path/to"
            }
            if source === target { return "error: source and target are the same topic" }
            var uid = target.attribute(ExtraTopic.topicUidAttr)
            if uid == nil {
                let generated = UUID().uuidString
                target.setAttribute(ExtraTopic.topicUidAttr, generated)
                uid = generated
            }
            source.setExtra(ExtraTopic(topicUID: uid!))
            effects.mapMutated = true
            return "linked \"\(source.text)\" → \"\(target.text)\""

        case "set_topic_collapsed":
            guard let collapsed = a.bool("collapsed") else { return "error: missing 'collapsed'" }
            guard let t = resolveTopic(a) else { return "error: no topic matches the given path/query" }
            t.setAttribute("collapsed", collapsed ? "true" : nil)
            effects.mapMutated = true
            return "set collapsed=\(collapsed) on \"\(t.text)\""

        default:
            return nil
        }
    }

    /// Resolve one endpoint of a two-endpoint tool: an explicit outline path key
    /// wins over a substring query key. Can't use `resolveTopic` since it reads
    /// the single shared `path`/`query` keys.
    private func resolveLinkEndpoint(_ a: ToolArgs, pathKey: String, queryKey: String) -> Topic? {
        if let path = a.str(pathKey) { return map.topic(atOutlinePath: path) }
        if let q = a.str(queryKey) { return firstTopic(matching: q) }
        return nil
    }
}
