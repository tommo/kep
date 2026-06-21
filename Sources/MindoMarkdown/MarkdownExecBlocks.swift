import Foundation
import CryptoKit

/// An executable code cell parsed from a markdown document — a fenced block
/// whose info string marks it runnable, e.g. ```` ```lua {exec} ```` or
/// ```` ```lua {exec id=trend} ````. Foundation of the Research Notebook
/// (epic #241): the host runs `code` through a kernel and caches the result
/// keyed by `hash`. Pure + line-based so MindoMarkdown stays free of any
/// scripting dependency.
public struct MarkdownExecBlock: Equatable, Sendable {
    /// Stable label from `id=…`, else a sequential `cell-N`.
    public let id: String
    /// Fence language token (e.g. "lua").
    public let language: String
    /// The cell body (inner lines, newline-joined).
    public let code: String

    public init(id: String, language: String, code: String) {
        self.id = id
        self.language = language
        self.code = code
    }

    /// Cache key — a content hash of the code, so edits invalidate the output.
    public var hash: String { MarkdownExecBlocks.hash(code) }
}

public enum MarkdownExecBlocks {

    /// All executable cells in `markdown`, in document order. A cell is a fenced
    /// block (``` or more backticks) whose info string's first token is a
    /// language and whose attributes contain `exec` (e.g. `lua {exec id=x}`).
    public static func parse(_ markdown: String) -> [MarkdownExecBlock] {
        var blocks: [MarkdownExecBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0
        var auto = 0
        while i < lines.count {
            guard let fence = opening(lines[i]) else { i += 1; continue }
            var body: [String] = []
            var j = i + 1
            var closed = false
            while j < lines.count {
                if isClosing(lines[j], minBackticks: fence.fenceLength) { closed = true; break }
                body.append(lines[j])
                j += 1
            }
            if fence.isExec {
                auto += 1
                blocks.append(MarkdownExecBlock(
                    id: fence.id ?? "cell-\(auto)",
                    language: fence.language,
                    code: body.joined(separator: "\n")))
            }
            i = closed ? j + 1 : j
        }
        return blocks
    }

    /// Lowercase hex SHA-256 of the code (the output-cache key).
    public static func hash(_ code: String) -> String {
        SHA256.hash(data: Data(code.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Fence parsing

    private struct Fence {
        let fenceLength: Int
        let language: String
        let isExec: Bool
        let id: String?
    }

    /// Parse a potential opening fence line. nil when the line isn't a fence.
    private static func opening(_ raw: String) -> Fence? {
        let line = raw.drop(while: { $0 == " " })   // tolerate small indent
        var ticks = 0
        for ch in line where ch == "`" { ticks += 1 }
        guard ticks >= 3, line.hasPrefix(String(repeating: "`", count: ticks)) else { return nil }
        let info = line.dropFirst(ticks).trimmingCharacters(in: .whitespaces)
        guard !info.isEmpty, !info.contains("`") else { return nil }   // closing/empty fence
        let language = String(info.prefix(while: { !$0.isWhitespace }))
        let isExec = info.range(of: #"(^|[\s{,])exec($|[\s},])"#, options: .regularExpression) != nil
        var id: String? = nil
        if let r = info.range(of: #"id\s*=\s*([A-Za-z0-9_-]+)"#, options: .regularExpression) {
            id = info[r].split(separator: "=").last.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return Fence(fenceLength: ticks, language: language, isExec: isExec, id: id)
    }

    private static func isClosing(_ raw: String, minBackticks: Int) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.allSatisfy({ $0 == "`" }) else { return false }
        return trimmed.count >= minBackticks
    }
}
