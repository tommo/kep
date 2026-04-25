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
    public var includeSuffixes: Set<String>?  // lowercased, e.g. {"mmd", "md"}
    public var maxHitsPerFile: Int
    public var maxFiles: Int

    public init(
        caseSensitive: Bool = false,
        includeSuffixes: Set<String>? = nil,
        maxHitsPerFile: Int = 50,
        maxFiles: Int = 500
    ) {
        self.caseSensitive = caseSensitive
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
        var hits: [SearchHit] = []
        let needle = options.caseSensitive ? query : query.lowercased()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, raw) in lines.enumerated() {
            let line = String(raw)
            let haystack = options.caseSensitive ? line : line.lowercased()
            var searchStart = haystack.startIndex
            while let range = haystack.range(of: needle, range: searchStart..<haystack.endIndex) {
                let utf16Start = line.utf16.distance(from: line.utf16.startIndex, to: range.lowerBound.samePosition(in: line.utf16) ?? line.utf16.startIndex)
                let utf16End = line.utf16.distance(from: line.utf16.startIndex, to: range.upperBound.samePosition(in: line.utf16) ?? line.utf16.endIndex)
                hits.append(SearchHit(
                    lineNumber: index + 1,
                    line: line,
                    matchRange: NSRange(location: utf16Start, length: utf16End - utf16Start)
                ))
                if hits.count >= options.maxHitsPerFile { return hits }
                searchStart = range.upperBound
            }
        }
        return hits
    }
}
