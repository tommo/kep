import Foundation
import Logging

/// One matched line inside a file. Mirrors `Anchor` from `mindolph-core`.
public struct SearchHit: Hashable, Sendable {
    public let lineNumber: Int   // 1-based
    public let line: String
    public let matchRange: NSRange   // range inside `line`

    public init(lineNumber: Int, line: String, matchRange: NSRange) {
        self.lineNumber = lineNumber
        self.line = line
        self.matchRange = matchRange
    }
}

extension SearchHit {
    /// The substring of `line` that this hit covers. Used by the mindmap
    /// canvas highlight path — Find-in-Files only knows the NSRange.
    public var matchedSubstring: String? {
        guard let range = Range(matchRange, in: line) else { return nil }
        let text = String(line[range])
        return text.isEmpty ? nil : text
    }
}

/// A file with at least one search hit. Mirrors `FoundFile`.
public struct FoundFile: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let hits: [SearchHit]

    public init(url: URL, hits: [SearchHit]) {
        self.url = url
        self.hits = hits
    }
}

/// Search options.
public struct SearchOptions: Sendable {
    public var caseSensitive: Bool
    /// When true the query is treated as an `NSRegularExpression` pattern.
    /// Mutually exclusive with `wholeWord` (regex authors handle their own
    /// boundaries); if both are set, `regex` wins.
    public var regex: Bool
    /// When true the query only matches at word boundaries (\b…\b in the
    /// generated regex). Ignored when `regex` is also true.
    public var wholeWord: Bool
    public var includeSuffixes: Set<String>?  // lowercased, e.g. {"mmd", "md"}
    public var maxHitsPerFile: Int
    public var maxFiles: Int

    public init(
        caseSensitive: Bool = false,
        regex: Bool = false,
        wholeWord: Bool = false,
        includeSuffixes: Set<String>? = nil,
        maxHitsPerFile: Int = 50,
        maxFiles: Int = 500
    ) {
        self.caseSensitive = caseSensitive
        self.regex = regex
        self.wholeWord = wholeWord
        self.includeSuffixes = includeSuffixes
        self.maxHitsPerFile = maxHitsPerFile
        self.maxFiles = maxFiles
    }
}

/// Workspace-scoped recursive text search. Mirrors `SearchService` from
/// `mindolph-core`, scoped down to the substring path that the app needs.
public final class SearchService {
    public static let shared = SearchService()
    private let logger = Logger(label: "mindo.core.search")

    public init() {}

    /// Walk every text file under `root`, line-by-line, collecting matches.
    /// Returns the files in the order they were discovered. `query` matching
    /// honors `options.caseSensitive`.
    public func search(in root: URL, query: String, options: SearchOptions = SearchOptions()) -> [FoundFile] {
        guard !query.isEmpty else { return [] }
        var results: [FoundFile] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        for case let url as URL in enumerator {
            if results.count >= options.maxFiles { break }
            guard accepts(url: url, options: options) else { continue }
            guard let hits = scan(file: url, query: query, options: options), !hits.isEmpty else { continue }
            results.append(FoundFile(url: url, hits: hits))
        }
        return results
    }

    private func accepts(url: URL, options: SearchOptions) -> Bool {
        // Skip directories and binary-likely files.
        let attrs = (try? url.resourceValues(forKeys: [.isRegularFileKey]))
        guard attrs?.isRegularFile == true else { return false }
        let suffix = url.pathExtension.lowercased()
        if let allowed = options.includeSuffixes, !allowed.isEmpty {
            return allowed.contains(suffix)
        }
        // Default include set: text-like extensions Mindo knows about.
        let textExtensions: Set<String> = ["mmd", "md", "puml", "csv", "txt", "json", "yaml", "yml", "html", "xml"]
        return textExtensions.contains(suffix)
    }

    /// Public so callers can scan a single file ad hoc.
    public func scan(file url: URL, query: String, options: SearchOptions) -> [SearchHit]? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return scan(text: text, query: query, options: options)
    }

    /// In-memory scan; exposed for tests.
    public func scan(text: String, query: String, options: SearchOptions = SearchOptions()) -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        // Pick the matching strategy once, outside the line loop. Regex and
        // whole-word both compile to NSRegularExpression so the inner loop
        // collects matches the same way; substring stays on String.range.
        let strategy: ScanStrategy
        if options.regex {
            guard let r = makeRegex(query, caseSensitive: options.caseSensitive) else { return [] }
            strategy = .regex(r)
        } else if options.wholeWord {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: query))\\b"
            guard let r = makeRegex(pattern, caseSensitive: options.caseSensitive) else { return [] }
            strategy = .regex(r)
        } else {
            strategy = .substring(options.caseSensitive ? query : query.lowercased(),
                                  caseSensitive: options.caseSensitive)
        }

        var hits: [SearchHit] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, raw) in lines.enumerated() {
            let line = String(raw)
            for matchRange in strategy.ranges(in: line) {
                hits.append(SearchHit(lineNumber: index + 1, line: line, matchRange: matchRange))
                if hits.count >= options.maxHitsPerFile { return hits }
            }
        }
        return hits
    }

    private func makeRegex(_ pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
        var opts: NSRegularExpression.Options = []
        if !caseSensitive { opts.insert(.caseInsensitive) }
        return try? NSRegularExpression(pattern: pattern, options: opts)
    }

    /// Per-line match driver. Substring goes through Swift's range-of-string
    /// (cheap), regex / whole-word go through NSRegularExpression.matches.
    private enum ScanStrategy {
        case substring(String, caseSensitive: Bool)
        case regex(NSRegularExpression)

        func ranges(in line: String) -> [NSRange] {
            switch self {
            case .substring(let needle, let caseSensitive):
                let haystack = caseSensitive ? line : line.lowercased()
                var result: [NSRange] = []
                var searchStart = haystack.startIndex
                while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
                    let utf16Start = line.utf16.distance(from: line.utf16.startIndex, to: range.lowerBound.samePosition(in: line.utf16) ?? line.utf16.startIndex)
                    let utf16End = line.utf16.distance(from: line.utf16.startIndex, to: range.upperBound.samePosition(in: line.utf16) ?? line.utf16.endIndex)
                    result.append(NSRange(location: utf16Start, length: utf16End - utf16Start))
                    searchStart = range.upperBound
                }
                return result
            case .regex(let regex):
                let nsLine = line as NSString
                let lineRange = NSRange(location: 0, length: nsLine.length)
                return regex.matches(in: line, range: lineRange).map(\.range)
            }
        }
    }
}
