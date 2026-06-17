import Foundation
import MindoCore

// G1 — Search & navigate (read-only). Implemented by the agent-tools sprint.
extension MindoAgentTools {
    static let searchDescriptors: [(name: String, description: String, parametersJSON: String)] = [
        ("search_workspace", "Search across all workspace documents line-by-line. Case-insensitive substring by default, or a regex when `regex` is true. Optionally limit to a file extension with `file_type` (e.g. \"md\"). Returns up to `max_hits` lines as \"<doc>:<line>: <text>\".",
         #"{"type":"object","properties":{"query":{"type":"string"},"regex":{"type":"boolean"},"file_type":{"type":"string"},"max_hits":{"type":"integer"}},"required":["query"]}"#),
        ("document_outline", "Return the markdown ATX heading outline (indented by level) of a workspace document.",
         #"{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}"#),
        ("read_section", "Return the body text under the first heading whose title contains `heading` (case-insensitive), up to the next heading of the same or higher level.",
         #"{"type":"object","properties":{"name":{"type":"string"},"heading":{"type":"string"}},"required":["name","heading"]}"#),
        ("outgoing_links", "List the distinct workspace document names this document links to via [[wiki links]].",
         #"{"type":"object","properties":{"name":{"type":"string"}},"required":["name"]}"#),
        ("semantic_search", "Find workspace passages most semantically relevant to a query using on-device embeddings (meaning-based; complements the literal search_workspace). Returns the top matches as 'doc [score]: passage'.",
         #"{"type":"object","properties":{"query":{"type":"string"},"k":{"type":"integer"}},"required":["query"]}"#),
    ]

    func handleSearch(_ name: String, _ a: ToolArgs) -> String? {
        switch name {
        case "search_workspace":
            guard let query = a.str("query") else { return "error: missing 'query'" }
            let useRegex = a.bool("regex") ?? false
            let fileType = a.str("file_type")?.lowercased()
            let maxHits = a.int("max_hits") ?? 40

            var matcher: ((String) -> Bool)
            if useRegex {
                guard let re = try? NSRegularExpression(pattern: query, options: [.caseInsensitive]) else {
                    return "error: invalid regex"
                }
                matcher = { line in
                    re.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
                }
            } else {
                let needle = query.lowercased()
                matcher = { line in line.lowercased().contains(needle) }
            }

            var hits: [String] = []
            outer: for entry in corpus {
                if let ext = fileType,
                   entry.url.pathExtension.lowercased() != ext { continue }
                let docName = entry.url.deletingPathExtension().lastPathComponent
                let lines = entry.text.components(separatedBy: "\n")
                for (i, line) in lines.enumerated() {
                    if matcher(line) {
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        hits.append("\(docName):\(i + 1): \(trimmed)")
                        if hits.count >= maxHits { break outer }
                    }
                }
            }
            return hits.isEmpty ? "(no matches)" : hits.joined(separator: "\n")

        case "document_outline":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            guard let text = documentText(named: docName) else { return "not found" }
            var out: [String] = []
            for line in text.components(separatedBy: "\n") {
                if let h = Self.parseHeading(line) {
                    out.append(String(repeating: "  ", count: h.level - 1) + h.title)
                }
            }
            return out.isEmpty ? "(no headings)" : out.joined(separator: "\n")

        case "read_section":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            guard let heading = a.str("heading") else { return "error: missing 'heading'" }
            guard let text = documentText(named: docName) else { return "not found" }
            let needle = heading.lowercased()
            let lines = text.components(separatedBy: "\n")
            var startLevel: Int?
            var body: [String] = []
            for line in lines {
                if let h = Self.parseHeading(line) {
                    if startLevel == nil {
                        if h.title.lowercased().contains(needle) {
                            startLevel = h.level
                        }
                        continue
                    } else if h.level <= startLevel! {
                        break
                    }
                }
                if startLevel != nil {
                    body.append(line)
                }
            }
            if startLevel == nil { return "not found" }
            // Trim leading/trailing blank lines for a clean result.
            while body.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { body.removeFirst() }
            while body.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { body.removeLast() }
            return body.isEmpty ? "(empty)" : body.joined(separator: "\n")

        case "outgoing_links":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            guard let text = documentText(named: docName) else { return "not found" }
            var seen = Set<String>()
            var names: [String] = []
            for link in WikiLinkParser.links(in: text) {
                guard !link.target.isEmpty else { continue }
                guard let url = WikiLinkResolver.resolve(link.target, in: allFiles) else { continue }
                let base = url.deletingPathExtension().lastPathComponent
                if seen.insert(base).inserted { names.append(base) }
            }
            return names.isEmpty ? "(none)" : names.joined(separator: ", ")

        case "semantic_search":
            guard let query = a.str("query") else { return "error: missing 'query'" }
            let embedder = NLTextEmbedder()
            guard embedder.isAvailable else {
                return "error: semantic search unavailable on this system — use search_workspace instead"
            }
            let docs = corpus.map { (doc: $0.url.deletingPathExtension().lastPathComponent, text: $0.text) }
            let index = SemanticIndex(documents: docs, embedder: embedder)
            guard index.chunkCount > 0 else { return "(no documents to search)" }
            let hits = index.query(query, embedder: embedder, topK: a.int("k") ?? 5)
            if hits.isEmpty { return "(no matches)" }
            return hits.map {
                let snippet = $0.text.replacingOccurrences(of: "\n", with: " ")
                let capped = snippet.count > 240 ? String(snippet.prefix(240)) + "…" : snippet
                return "\($0.doc) [\(String(format: "%.2f", $0.score))]: \(capped)"
            }.joined(separator: "\n\n")

        default:
            return nil
        }
    }

    /// Parse a markdown ATX heading line (`^#{1,6}\s+title`). Returns nil otherwise.
    private static func parseHeading(_ line: String) -> (level: Int, title: String)? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#" {
            level += 1
            idx = line.index(after: idx)
        }
        guard level >= 1, level <= 6, idx < line.endIndex,
              line[idx] == " " || line[idx] == "\t" else { return nil }
        let title = line[idx...].trimmingCharacters(in: .whitespaces)
        return (level, title)
    }
}
