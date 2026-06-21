import Foundation

/// One cell of a Research Notebook (`.mnb`). Prose cells are markdown; code
/// cells are executable (Lua today). The on-disk format is plain markdown —
/// prose verbatim, code cells as ```` ```lang {exec id=…} ```` fences — so a
/// `.mnb` stays diffable/mergeable and interoperable with the markdown tools.
public enum NotebookCell: Equatable, Sendable, Identifiable {
    case prose(id: String, text: String)
    case code(id: String, language: String, code: String)

    public var id: String {
        switch self {
        case .prose(let id, _): return id
        case .code(let id, _, _): return id
        }
    }

    /// Cache key for a code cell's output (nil for prose).
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

    public static func parse(_ text: String) -> Notebook {
        var prose = 0
        let cells: [NotebookCell] = MarkdownExecBlocks.scan(text).map { seg in
            switch seg {
            case .prose(let t):
                prose += 1
                // Trim the blank lines that separated this run from adjacent
                // fences so serialize→parse round-trips stably (cells are
                // re-joined with a blank line).
                return .prose(id: "prose-\(prose)", text: t.trimmingCharacters(in: .whitespacesAndNewlines))
            case .exec(let b):
                return .code(id: b.id, language: b.language, code: b.code)
            }
        }
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
            }
        }.joined(separator: "\n\n")
    }
}
