import Foundation

/// One cell of a Research Notebook (`.mnb`). Prose cells are markdown; code
/// cells are executable (Lua today); agent cells are a first-class, attributed,
/// re-runnable block — a research prompt plus the agent's authored result. The
/// on-disk format is plain markdown — prose verbatim, code cells as
/// ```` ```lang {exec id=…} ```` fences, agent cells as an HTML-comment-
/// delimited region — so a `.mnb` stays diffable/mergeable.
public enum NotebookCell: Equatable, Sendable, Identifiable {
    case prose(id: String, text: String)
    case code(id: String, language: String, code: String)
    case agent(id: String, prompt: String, result: String, sources: [String])

    public var id: String {
        switch self {
        case .prose(let id, _): return id
        case .code(let id, _, _): return id
        case .agent(let id, _, _, _): return id
        }
    }

    /// Cache key for a code cell's output (nil for prose/agent).
    public var outputHash: String? {
        if case .code(_, _, let code) = self { return MarkdownExecBlocks.hash(code) }
        return nil
    }
}

public struct Notebook: Equatable, Sendable {
    public var cells: [NotebookCell]
    public init(cells: [NotebookCell] = []) { self.cells = cells }

    public var codeCells: [NotebookCell] { cells.filter { if case .code = $0 { return true } else { return false } } }
}

/// Parse/serialize the markdown ⇄ Notebook cell model.
public enum NotebookFormat {
    static let agentOpenPrefix = "<!--mindo:agent "
    static let agentClose = "<!--/mindo:agent-->"

    public static func parse(_ text: String) -> Notebook {
        var cells: [NotebookCell] = []
        var proseN = 0, agentN = 0
        let lines = text.components(separatedBy: "\n")

        // Append prose/code cells for a plain (non-agent) markdown run.
        func appendPlain(_ chunk: String) {
            guard !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            for seg in MarkdownExecBlocks.scan(chunk) {
                switch seg {
                case .prose(let t):
                    proseN += 1
                    cells.append(.prose(id: "prose-\(proseN)", text: t.trimmingCharacters(in: .whitespacesAndNewlines)))
                case .exec(let b):
                    cells.append(.code(id: b.id, language: b.language, code: b.code))
                }
            }
        }

        var plain: [String] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix(agentOpenPrefix), line.hasSuffix("-->") {
                appendPlain(plain.joined(separator: "\n")); plain.removeAll()
                let prompt = decodePrompt(from: line)
                var body: [String] = []
                var j = i + 1
                while j < lines.count, lines[j] != agentClose { body.append(lines[j]); j += 1 }
                agentN += 1
                cells.append(.agent(id: "agent-\(agentN)", prompt: prompt.text,
                                    result: body.joined(separator: "\n"), sources: prompt.sources))
                i = (j < lines.count) ? j + 1 : j   // skip the close marker
            } else {
                plain.append(line); i += 1
            }
        }
        appendPlain(plain.joined(separator: "\n"))
        return Notebook(cells: cells)
    }

    public static func serialize(_ notebook: Notebook) -> String {
        notebook.cells.map { cell in
            switch cell {
            case .prose(_, let text):
                return text
            case .code(let id, let language, let code):
                let lang = language.isEmpty ? "lua" : language
                return "```\(lang) {exec id=\(id)}\n\(code)\n```"
            case .agent(_, let prompt, let result, let sources):
                return "\(agentOpenPrefix)\(encodeMeta(prompt: prompt, sources: sources))-->\n\(result)\n\(agentClose)"
            }
        }.joined(separator: "\n\n")
    }

    // MARK: - Agent meta codec (JSON in the open comment — survives quotes/newlines)

    private static func encodeMeta(prompt: String, sources: [String]) -> String {
        var obj: [String: Any] = ["prompt": prompt]
        if !sources.isEmpty { obj["sources"] = sources }
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{\"prompt\":\"\"}"
    }
    private static func decodePrompt(from openLine: String) -> (text: String, sources: [String]) {
        // strip "<!--mindo:agent " prefix and "-->" suffix → JSON object
        var json = String(openLine.dropFirst(agentOpenPrefix.count))
        if json.hasSuffix("-->") { json = String(json.dropLast(3)) }
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ("", []) }
        return (obj["prompt"] as? String ?? "", obj["sources"] as? [String] ?? [])
    }
}
