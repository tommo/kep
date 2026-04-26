import Foundation

/// Pure-logic line-comment toggle for PlantUML source. Mirrors the
/// `' ` line-comment behavior of mindolph's PlantUmlToolbar — if every
/// non-blank line in the block already starts with `' `, the prefix is
/// removed; otherwise the prefix is added to every non-blank line.
/// Blank lines are left as-is so a partial selection across paragraphs
/// doesn't create stray `' ` lines.
public enum PlantUMLCommentToggle {

    public static let prefix: String = "' "

    public static func toggle(_ block: String) -> String {
        let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !nonBlank.isEmpty else { return block }
        let allCommented = nonBlank.allSatisfy { isCommented($0) }
        let mapped: [String] = lines.map { line in
            if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
            return allCommented ? stripPrefix(line) : prefix + line
        }
        return mapped.joined(separator: "\n")
    }

    /// PlantUML treats `'` (with or without trailing space) as the
    /// line-comment marker. We accept either form when stripping so a
    /// hand-typed `'foo` round-trips cleanly.
    private static func isCommented(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        return trimmed.first == "'"
    }

    private static func stripPrefix(_ line: String) -> String {
        guard let idx = line.firstIndex(where: { $0 != " " && $0 != "\t" }) else { return line }
        let leading = line[..<idx]
        var rest = line[idx...]
        guard rest.first == "'" else { return line }
        rest = rest.dropFirst()
        if rest.first == " " { rest = rest.dropFirst() }
        return String(leading) + String(rest)
    }
}
