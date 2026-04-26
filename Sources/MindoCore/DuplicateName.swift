import Foundation

/// Pure helper for the "Duplicate file" sidebar action — finds the next
/// unused " copy", " copy 2", " copy 3"… name in a directory. Lives in
/// MindoCore so the naming rule is unit-testable without touching the
/// real filesystem (caller injects the existence check).
public enum DuplicateName {

    /// Return the URL the duplicated file should land at. Tries
    /// `<stem> copy.<ext>`, then `<stem> copy 2.<ext>`, etc. until
    /// `exists(_:)` returns false. Empty extensions are handled (no
    /// trailing `.`).
    public static func uniqueURL(
        in directory: URL,
        stem: String,
        ext: String,
        exists: (URL) -> Bool
    ) -> URL {
        for candidate in candidateNames(stem: stem, ext: ext) {
            let url = directory.appendingPathComponent(candidate)
            if !exists(url) { return url }
        }
        // Practically unreachable — the sequence is unbounded — but keep a
        // defined fallback rather than crashing.
        return directory.appendingPathComponent("\(stem) copy.\(ext)")
    }

    /// Lazy sequence of candidate filenames. Exposed for tests.
    public static func candidateNames(stem: String, ext: String) -> AnySequence<String> {
        let suffix = ext.isEmpty ? "" : ".\(ext)"
        return AnySequence(sequence(state: 0) { (counter: inout Int) -> String? in
            counter += 1
            if counter == 1 { return "\(stem) copy\(suffix)" }
            return "\(stem) copy \(counter)\(suffix)"
        })
    }
}
