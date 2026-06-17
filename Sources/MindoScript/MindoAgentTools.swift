import Foundation
import MindoModel
import MindoCore

/// The concrete behaviour behind the agent's tool calls — operations over a mind
/// map and the knowledge base. Takes a tool name + JSON arguments and returns a
/// string result to feed back to the model. Pure host logic (no LLM, no UI), so
/// it's unit-tested directly; the app maps `ToolCall` → here and exposes the
/// specs as `ToolSpec`s.
public struct MindoAgentTools {
    public let map: MindMap
    public let corpus: [(url: URL, text: String)]
    public let allFiles: [URL]

    public init(map: MindMap,
                corpus: [(url: URL, text: String)] = [],
                allFiles: [URL] = []) {
        self.map = map
        self.corpus = corpus
        self.allFiles = allFiles
    }

    /// Tool descriptions (name, human description, JSON-schema params) the app
    /// turns into `ToolSpec`s offered to the model.
    public static let descriptors: [(name: String, description: String, parametersJSON: String)] = [
        ("list_docs", "List the names of all documents in the workspace.",
         #"{"type":"object","properties":{}}"#),
        ("resolve_link", "Resolve a [[wiki link]] target to a workspace document name, or 'not found'.",
         #"{"type":"object","properties":{"target":{"type":"string"}},"required":["target"]}"#),
        ("backlinks", "List documents that link to the named document.",
         #"{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}"#),
        ("read_document", "Read the full text of a workspace document by name.",
         #"{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}"#),
        ("find_topics", "List mind-map topics whose text contains a substring (case-insensitive).",
         #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}"#),
        ("add_child_topic", "Add a child topic. Without 'parent' it goes under the root; with 'parent' (a substring of an existing topic) it goes under the first matching topic.",
         #"{"type":"object","properties":{"text":{"type":"string"},"parent":{"type":"string"}},"required":["text"]}"#),
        ("run_lua", "Run a Lua script against the mind map via the `mindo` API; returns its result.",
         #"{"type":"object","properties":{"script":{"type":"string"}},"required":["script"]}"#),
    ]

    /// Execute a tool by name. Unknown tools and bad arguments return an error
    /// string (fed back to the model rather than thrown).
    public func handle(name: String, argumentsJSON: String) -> String {
        let args = Self.parseArgs(argumentsJSON)
        func str(_ key: String) -> String? { args[key] as? String }

        switch name {
        case "list_docs":
            let names = allFiles.map { $0.deletingPathExtension().lastPathComponent }
            return names.isEmpty ? "(no documents)" : names.joined(separator: ", ")

        case "resolve_link":
            guard let target = str("target") else { return "error: missing 'target'" }
            guard let url = WikiLinkResolver.resolve(target, in: allFiles) else { return "not found" }
            return url.deletingPathExtension().lastPathComponent

        case "backlinks":
            guard let docName = str("name") else { return "error: missing 'name'" }
            guard let target = WikiLinkResolver.resolve(docName, in: allFiles) else { return "not found" }
            let sources = Backlinks.sources(to: target, corpus: corpus, allFiles: allFiles)
                .map { $0.deletingPathExtension().lastPathComponent }
            return sources.isEmpty ? "(none)" : sources.joined(separator: ", ")

        case "read_document":
            guard let name = str("name") else { return "error: missing 'name'" }
            guard let url = WikiLinkResolver.resolve(name, in: allFiles),
                  let entry = corpus.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL })
            else { return "not found" }
            if entry.text.isEmpty { return "(empty)" }
            let cap = 12_000
            return entry.text.count > cap ? String(entry.text.prefix(cap)) + "\n…(truncated)" : entry.text

        case "find_topics":
            guard let query = str("query") else { return "error: missing 'query'" }
            guard let root = map.root else { return "(none)" }
            let needle = query.lowercased()
            var hits: [String] = []
            root.traverse { if $0.text.lowercased().contains(needle) { hits.append($0.text) } }
            return hits.isEmpty ? "(none)" : hits.joined(separator: "\n")

        case "add_child_topic":
            guard let text = str("text") else { return "error: missing 'text'" }
            let parent: Topic
            if let q = str("parent"), !q.isEmpty {
                guard let found = firstTopic(matching: q) else { return "error: no topic matches \"\(q)\"" }
                parent = found
            } else {
                parent = map.root ?? { let r = Topic(text: "Root"); map.root = r; return r }()
            }
            _ = parent.addChild(text: text)
            return "added \"\(text)\" under \"\(parent.text)\""

        case "run_lua":
            guard let script = str("script") else { return "error: missing 'script'" }
            let result = MindoScriptRunner.run(script, on: map, corpus: corpus, allFiles: allFiles)
            return result.error.map { "error: \($0)" } ?? result.output

        default:
            return "error: unknown tool '\(name)'"
        }
    }

    /// First topic (pre-order) whose text contains `query`, case-insensitive.
    private func firstTopic(matching query: String) -> Topic? {
        guard let root = map.root else { return nil }
        let needle = query.lowercased()
        var hit: Topic?
        root.traverse { if hit == nil, $0.text.lowercased().contains(needle) { hit = $0 } }
        return hit
    }

    static func parseArgs(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }
}
