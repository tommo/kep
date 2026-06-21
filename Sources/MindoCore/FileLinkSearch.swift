import Foundation

/// Finds documents that reference a target file by a relative/absolute FILE
/// PATH — e.g. a Markdown link `[notes](sub/notes.md)` or image
/// `![](img/diagram.png)` — as opposed to `[[wiki links]]` (which `Backlinks`
/// covers). javamind parity: `SearchService.searchLinksInFilesIn` /
/// `FileLinkSearchMatcher`. Pure + path-based so it's unit-testable without disk.
public enum FileLinkSearch {

    /// Source documents whose text links to `target` by a file path, each with
    /// the trimmed context line around every such link. A path in a source is
    /// resolved relative to THAT source's directory (the same way a Markdown
    /// renderer / click would). External (`http(s):`, `mailto:`…) and bare
    /// `#anchor` links are ignored; the target never references itself.
    public static func referencing(_ target: URL,
                                   corpus: [(url: URL, text: String)]) -> [LinkedMention] {
        let targetStd = target.standardizedFileURL
        var out: [LinkedMention] = []
        for entry in corpus {
            if entry.url.standardizedFileURL == targetStd { continue }
            let baseDir = entry.url.deletingLastPathComponent()
            var snippets: [String] = []
            for (path, range) in markdownLinkPaths(in: entry.text) {
                guard let resolved = resolve(path, relativeTo: baseDir),
                      resolved.standardizedFileURL == targetStd else { continue }
                snippets.append(Backlinks.contextLine(in: entry.text, around: range))
            }
            if !snippets.isEmpty {
                out.append(LinkedMention(source: entry.url, snippets: snippets))
            }
        }
        return out.sorted { $0.source.path < $1.source.path }
    }

    /// Resolve a Markdown link path to a file URL, or nil for external / anchor
    /// / empty links. Strips a trailing `#fragment` or `?query` and any
    /// surrounding angle brackets.
    static func resolve(_ raw: String, relativeTo base: URL) -> URL? {
        var path = raw.trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("<") && path.hasSuffix(">") { path = String(path.dropFirst().dropLast()) }
        guard !path.isEmpty, !path.hasPrefix("#") else { return nil }
        if path.contains("://") { return nil }                 // http(s), file://, etc.
        if path.hasPrefix("mailto:") || path.hasPrefix("tel:") { return nil }
        // Drop a #fragment / ?query suffix.
        if let i = path.firstIndex(where: { $0 == "#" || $0 == "?" }) { path = String(path[..<i]) }
        guard !path.isEmpty else { return nil }
        let decoded = path.removingPercentEncoding ?? path
        if decoded.hasPrefix("/") {
            return URL(fileURLWithPath: decoded).standardizedFileURL
        }
        return URL(fileURLWithPath: decoded, relativeTo: base).standardizedFileURL
    }

    /// Every Markdown link/image URL in `text` with its source range. Matches
    /// the `](URL)` tail shared by `[text](URL)` and `![alt](URL)`, taking the
    /// URL up to the first whitespace (so `](path "title")` keeps just the path).
    static func markdownLinkPaths(in text: String) -> [(path: String, range: NSRange)] {
        let ns = text as NSString
        let re = try! NSRegularExpression(pattern: "\\]\\(([^)]*)\\)")
        var out: [(String, NSRange)] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let inner = ns.substring(with: m.range(at: 1))
            // URL is the part before an optional ` "title"` — split on whitespace.
            let urlPart = inner.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? inner
            out.append((urlPart, m.range))
        }
        return out
    }
}
