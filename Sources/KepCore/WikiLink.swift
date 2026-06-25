import Foundation

/// A parsed `[[wiki link]]` reference found in document text — the building
/// block of Kep's in-project knowledge base. Supports Obsidian-style forms:
///   [[Doc]]            → target "Doc"
///   [[Doc#Heading]]    → target "Doc", heading "Heading"
///   [[Doc|alias text]] → target "Doc", alias "alias text"
///   [[#Heading]]       → in-document heading link (empty target)
public struct WikiLink: Equatable, Sendable {
    /// UTF-16 offset range of the whole `[[…]]` token in the source string —
    /// usable for NSTextView styling / hit-testing.
    public let nsRange: NSRange
    public let target: String      // doc name, no extension required; "" = same doc
    public let heading: String?
    public let alias: String?

    public init(nsRange: NSRange, target: String, heading: String? = nil, alias: String? = nil) {
        self.nsRange = nsRange
        self.target = target
        self.heading = heading
        self.alias = alias
    }

    /// What the user sees rendered for this link.
    public var displayText: String {
        if let alias, !alias.isEmpty { return alias }
        if let heading, !heading.isEmpty { return target.isEmpty ? "#\(heading)" : "\(target)#\(heading)" }
        return target
    }
}

public enum WikiLinkParser {
    // [[ ... ]] with no nested ] inside; non-greedy inner capture.
    private static let regex = try! NSRegularExpression(pattern: "\\[\\[([^\\[\\]]+?)\\]\\]")

    /// Extract every wiki link in `text`, in source order.
    public static func links(in text: String) -> [WikiLink] {
        let full = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: full).compactMap { m in
            guard let innerR = Range(m.range(at: 1), in: text) else { return nil }
            return parseInner(String(text[innerR]), token: m.range)
        }
    }

    /// Parse the bit between the brackets into target / heading / alias.
    private static func parseInner(_ inner: String, token: NSRange) -> WikiLink? {
        // alias = everything after the first '|'
        var body = inner
        var alias: String?
        if let pipe = inner.firstIndex(of: "|") {
            alias = String(inner[inner.index(after: pipe)...]).trimmingCharacters(in: .whitespaces)
            body = String(inner[..<pipe])
        }
        // heading = everything after the first '#'
        var target = body
        var heading: String?
        if let hash = body.firstIndex(of: "#") {
            heading = String(body[body.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
            target = String(body[..<hash])
        }
        target = target.trimmingCharacters(in: .whitespaces)
        // Reject an empty token like [[]] or [[ | ]].
        if target.isEmpty && (heading?.isEmpty ?? true) { return nil }
        return WikiLink(nsRange: token, target: target,
                        heading: heading?.isEmpty == true ? nil : heading,
                        alias: alias?.isEmpty == true ? nil : alias)
    }
}

public enum WikiLinkResolver {
    /// Resolve a wiki `target` to a workspace file URL. Matching is by file
    /// name, case-insensitive, preferring (1) an exact full-name match
    /// (`notes.md` ⇄ notes.md), then (2) a base-name match ignoring extension
    /// (`notes` ⇄ notes.md). When several files share a base name, the
    /// shortest path wins (closest to the workspace root) for determinism.
    public static func resolve(_ target: String, in files: [URL]) -> URL? {
        let needle = target.lowercased()
        guard !needle.isEmpty else { return nil }

        func score(_ url: URL) -> Int? {
            let name = url.lastPathComponent.lowercased()
            let base = url.deletingPathExtension().lastPathComponent.lowercased()
            if name == needle { return 0 }       // exact incl. extension
            if base == needle { return 1 }       // base name (no extension)
            return nil
        }
        return files
            .compactMap { url -> (URL, Int)? in score(url).map { (url, $0) } }
            .min { a, b in
                a.1 != b.1 ? a.1 < b.1 : a.0.path.count < b.0.path.count
            }?
            .0
    }
}
