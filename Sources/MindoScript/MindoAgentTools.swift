import Foundation
import MindoModel
import MindoCore

/// Records side effects of tool calls (disk writes, map mutation) so the host
/// app can refresh affected tabs / the sidebar after the agent loop. A
/// reference type so the value-type `MindoAgentTools` can append to it.
public final class AgentToolEffects {
    public var changedFiles: Set<URL> = []
    public var createdFiles: Set<URL> = []
    public var mapMutated = false
    public init() {}
}

/// Lightweight typed accessor over the decoded JSON argument dictionary.
public struct ToolArgs {
    public let dict: [String: Any]
    public init(_ dict: [String: Any]) { self.dict = dict }

    public func str(_ key: String) -> String? {
        guard let v = dict[key] as? String, !v.isEmpty else { return nil }
        return v
    }
    public func int(_ key: String) -> Int? {
        if let i = dict[key] as? Int { return i }
        if let d = dict[key] as? Double { return Int(d) }
        if let s = dict[key] as? String { return Int(s) }
        return nil
    }
    public func bool(_ key: String) -> Bool? {
        if let b = dict[key] as? Bool { return b }
        if let s = dict[key] as? String { return ["true", "1", "yes", "on"].contains(s.lowercased()) }
        return nil
    }
}

/// The concrete behaviour behind the agent's tool calls — operations over a mind
/// map and the knowledge base. Takes a tool name + JSON arguments and returns a
/// string result to feed back to the model. Pure host logic (no LLM, no UI), so
/// it's unit-tested directly; the app maps `ToolCall` → here and exposes the
/// specs as `ToolSpec`s.
///
/// Tools are split across composable group files (`MindoAgentTools+*.swift`),
/// each contributing a `*Descriptors` array and a `handle*` method that returns
/// nil for tools it doesn't own. `descriptors`/`handle` aggregate them.
public struct MindoAgentTools {
    public let map: MindMap
    public let corpus: [(url: URL, text: String)]
    public let allFiles: [URL]
    /// Directory new documents are created in when a name doesn't resolve to an
    /// existing file. Falls back to the first known file's folder.
    public let workspaceRoot: URL?
    public let effects: AgentToolEffects

    public init(map: MindMap,
                corpus: [(url: URL, text: String)] = [],
                allFiles: [URL] = [],
                workspaceRoot: URL? = nil,
                effects: AgentToolEffects = AgentToolEffects()) {
        self.map = map
        self.corpus = corpus
        self.allFiles = allFiles
        self.workspaceRoot = workspaceRoot
        self.effects = effects
    }

    /// All tool descriptors (name, human description, JSON-schema params) the app
    /// turns into `ToolSpec`s. Core tools + every group.
    public static var descriptors: [(name: String, description: String, parametersJSON: String)] {
        coreDescriptors
            + searchDescriptors
            + docEditDescriptors
            + mindmapEditDescriptors
            + topicExtrasDescriptors
    }

    static let coreDescriptors: [(name: String, description: String, parametersJSON: String)] = [
        ("list_docs", "List the names of all documents in the workspace.",
         #"{"type":"object","properties":{}}"#),
        ("resolve_link", "Resolve a [[wiki link]] target to a workspace document name, or 'not found'.",
         #"{"type":"object","properties":{"target":{"type":"string"}},"required":["target"]}"#),
        ("backlinks", "List documents that link to the named document.",
         #"{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}"#),
        ("read_document", "Read the full text of a workspace document by name.",
         #"{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}"#),
        ("get_mindmap", "Return the active mind map as an indented outline. Each line is prefixed with its stable [outline-path] (e.g. [0/2]) that other topic tools accept as `path`.",
         #"{"type":"object","properties":{}}"#),
        ("find_topics", "List mind-map topics whose text contains a substring (case-insensitive). Each hit is prefixed with its [outline-path].",
         #"{"type":"object","properties":{"query":{"type":"string"}},"required":["query"]}"#),
        ("add_child_topic", "Add a child topic. Target the parent by `path` (stable outline path) or `parent` (substring of an existing topic); without either it goes under the root. Optional `index` positions it among siblings.",
         #"{"type":"object","properties":{"text":{"type":"string"},"parent":{"type":"string"},"path":{"type":"string"},"index":{"type":"integer"}},"required":["text"]}"#),
        ("rename_topic", "Rename a topic (targeted by `path` or `query` substring) to `text`.",
         #"{"type":"object","properties":{"query":{"type":"string"},"path":{"type":"string"},"text":{"type":"string"}},"required":["text"]}"#),
        ("remove_topic", "Delete a topic and its subtree, targeted by `path` or `query` substring.",
         #"{"type":"object","properties":{"query":{"type":"string"},"path":{"type":"string"}}}"#),
        ("set_topic_attr", "Set a topic attribute (e.g. fillColor, textColor) on a topic targeted by `path` or `query`. Omit 'value' to clear it.",
         #"{"type":"object","properties":{"query":{"type":"string"},"path":{"type":"string"},"key":{"type":"string"},"value":{"type":"string"}},"required":["key"]}"#),
        ("run_lua", "Run a Lua script against the mind map via the `mindo` API; returns its result.",
         #"{"type":"object","properties":{"script":{"type":"string"}},"required":["script"]}"#),
    ]

    /// Execute a tool by name. Unknown tools and bad arguments return an error
    /// string (fed back to the model rather than thrown).
    public func handle(name: String, argumentsJSON: String) -> String {
        let a = ToolArgs(Self.parseArgs(argumentsJSON))
        return handleCore(name, a)
            ?? handleSearch(name, a)
            ?? handleDocEdit(name, a)
            ?? handleMindmapEdit(name, a)
            ?? handleTopicExtras(name, a)
            ?? "error: unknown tool '\(name)'"
    }

    /// Core tool group. Returns nil if `name` isn't one of ours.
    func handleCore(_ name: String, _ a: ToolArgs) -> String? {
        switch name {
        case "list_docs":
            let names = allFiles.map { $0.deletingPathExtension().lastPathComponent }
            return names.isEmpty ? "(no documents)" : names.joined(separator: ", ")

        case "resolve_link":
            guard let target = a.str("target") else { return "error: missing 'target'" }
            guard let url = WikiLinkResolver.resolve(target, in: allFiles) else { return "not found" }
            return url.deletingPathExtension().lastPathComponent

        case "backlinks":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            guard let target = WikiLinkResolver.resolve(docName, in: allFiles) else { return "not found" }
            let sources = Backlinks.sources(to: target, corpus: corpus, allFiles: allFiles)
                .map { $0.deletingPathExtension().lastPathComponent }
            return sources.isEmpty ? "(none)" : sources.joined(separator: ", ")

        case "read_document":
            guard let name = a.str("name") else { return "error: missing 'name'" }
            guard let text = documentText(named: name) else { return "not found" }
            if text.isEmpty { return "(empty)" }
            let cap = 12_000
            return text.count > cap ? String(text.prefix(cap)) + "\n…(truncated)" : text

        case "get_mindmap":
            guard let root = map.root else { return "(empty mind map)" }
            var out = ""
            Self.outline(root, path: "", depth: 0, into: &out)
            return out

        case "find_topics":
            guard let query = a.str("query") else { return "error: missing 'query'" }
            guard map.root != nil else { return "(none)" }
            let needle = query.lowercased()
            var hits: [String] = []
            forEachTopic { t in
                if t.text.lowercased().contains(needle) {
                    hits.append("[\(Self.outlinePath(of: t))] \(t.text)")
                }
            }
            return hits.isEmpty ? "(none)" : hits.joined(separator: "\n")

        case "add_child_topic":
            guard let text = a.str("text") else { return "error: missing 'text'" }
            let parent: Topic
            if a.str("path") != nil || a.str("parent") != nil {
                guard let found = resolveTopic(a, queryKey: "parent") else {
                    return "error: no topic matches the given path/parent"
                }
                parent = found
            } else {
                parent = map.root ?? { let r = Topic(text: "Root"); map.root = r; return r }()
            }
            let child = parent.addChild(text: text)
            if let idx = a.int("index") { parent.move(child: child, to: idx) }
            effects.mapMutated = true
            return "added \"\(text)\" under \"\(parent.text)\" at [\(Self.outlinePath(of: child))]"

        case "rename_topic":
            guard let text = a.str("text") else { return "error: missing 'text'" }
            guard let t = resolveTopic(a) else { return "error: no topic matches the given path/query" }
            let old = t.text
            t.text = text
            effects.mapMutated = true
            return "renamed \"\(old)\" → \"\(text)\""

        case "remove_topic":
            guard let t = resolveTopic(a) else { return "error: no topic matches the given path/query" }
            guard let parent = t.parent else { return "error: can't remove the root topic" }
            let gone = t.text
            parent.removeChild(t)
            effects.mapMutated = true
            return "removed \"\(gone)\""

        case "set_topic_attr":
            guard let key = a.str("key") else { return "error: missing 'key'" }
            guard let t = resolveTopic(a) else { return "error: no topic matches the given path/query" }
            t.setAttribute(key, a.str("value"))   // nil value clears
            effects.mapMutated = true
            return "set @\(key)=\(a.str("value") ?? "nil") on \"\(t.text)\""

        case "run_lua":
            guard let script = a.str("script") else { return "error: missing 'script'" }
            let result = MindoScriptRunner.run(script, on: map, corpus: corpus, allFiles: allFiles)
            effects.mapMutated = true
            return result.error.map { "error: \($0)" } ?? result.output

        default:
            return nil
        }
    }

    // MARK: - Shared helpers (used by all tool groups)

    /// Render a topic subtree as an indented outline, each line prefixed with
    /// its stable [outline-path].
    static func outline(_ topic: Topic, path: String, depth: Int, into out: inout String) {
        out += String(repeating: "  ", count: depth) + "[\(path.isEmpty ? "" : path)] " + topic.text + "\n"
        for (i, child) in topic.children.enumerated() {
            let childPath = path.isEmpty ? "\(i)" : "\(path)/\(i)"
            outline(child, path: childPath, depth: depth + 1, into: &out)
        }
    }

    /// Outline path of a topic ("" for root, "0/2" for the 3rd child of the
    /// 1st child of root), computed by walking up to the root.
    static func outlinePath(of topic: Topic) -> String {
        var comps: [String] = []
        var node = topic
        while let parent = node.parent {
            guard let idx = parent.children.firstIndex(where: { $0 === node }) else { break }
            comps.append(String(idx))
            node = parent
        }
        return comps.reversed().joined(separator: "/")
    }

    /// Resolve a topic from args: `path` (stable outline path) wins, else a
    /// substring `query` (or an alternate key, e.g. "parent"). First match wins.
    func resolveTopic(_ a: ToolArgs, queryKey: String = "query") -> Topic? {
        if let path = a.str("path") { return map.topic(atOutlinePath: path) }
        if let q = a.str(queryKey) { return firstTopic(matching: q) }
        return nil
    }

    /// First topic (pre-order) whose text contains `query`, case-insensitive.
    func firstTopic(matching query: String) -> Topic? {
        let needle = query.lowercased()
        var hit: Topic?
        forEachTopic { if hit == nil, $0.text.lowercased().contains(needle) { hit = $0 } }
        return hit
    }

    /// Pre-order visit of every topic.
    func forEachTopic(_ visit: (Topic) -> Void) {
        map.root?.traverse(visit)
    }

    /// Text of a workspace document by name, from the in-memory corpus (falls
    /// back to reading disk if the corpus doesn't carry it).
    func documentText(named name: String) -> String? {
        guard let url = WikiLinkResolver.resolve(name, in: allFiles) else { return nil }
        if let entry = corpus.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            return entry.text
        }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// URL of an existing document by name, or nil.
    func documentURL(named name: String) -> URL? {
        WikiLinkResolver.resolve(name, in: allFiles)
    }

    /// Resolve a name to an existing file, or build a URL for a new file of the
    /// given extension under the workspace root. nil when no creation dir known.
    func resolveOrCreateURL(name: String, ext: String) -> URL? {
        if let existing = WikiLinkResolver.resolve(name, in: allFiles) { return existing }
        guard let dir = workspaceRoot ?? allFiles.first?.deletingLastPathComponent() else { return nil }
        let base = name.hasSuffix(".\(ext)") ? name : "\(name).\(ext)"
        // Guard against path traversal: only the last path component is used.
        let safe = (base as NSString).lastPathComponent
        return dir.appendingPathComponent(safe)
    }

    /// Write text to a document URL, recording the effect. Returns a status line.
    func writeDocument(_ url: URL, _ content: String, created: Bool) -> String {
        do {
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
            if created { effects.createdFiles.insert(url) }
            effects.changedFiles.insert(url)
            let n = url.deletingPathExtension().lastPathComponent
            return created ? "created \"\(n)\" (\(content.count) chars)" : "wrote \"\(n)\" (\(content.count) chars)"
        } catch {
            return "error: write failed — \(error.localizedDescription)"
        }
    }

    static func parseArgs(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
    }
}
