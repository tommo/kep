import Foundation

/// Pure autocomplete logic for `[[wiki links]]` in the markdown editor: given the
/// text on the current line up to the caret, decide whether the caret sits in the
/// *document-name* position of an open `[[ … ]]` and, if so, which workspace
/// document names match what's been typed.
///
/// Kept free of AppKit so the bracket-context detection is unit-testable; the text
/// view supplies `lineUpToCaret` and the candidate names and maps the result back
/// onto an `NSRange`.
public enum WikiLinkCompletion {

    /// The doc-name fragment the user is typing inside an open `[[`, or nil when
    /// the caret isn't in a completable name position. Returns "" right after
    /// `[[` (nothing typed yet — offer everything).
    ///
    /// Not completable: no open `[[` on the line; the `[[` is already closed by a
    /// later `]]`; or the caret is past a `#` (heading) or `|` (alias) where a doc
    /// name no longer applies.
    public static func partial(inLineUpToCaret line: String) -> String? {
        guard let openRange = line.range(of: "[[", options: .backwards) else { return nil }
        let after = line[openRange.upperBound...]
        // A `]]` after the last `[[` means the link is already closed.
        if after.contains("]]") { return nil }
        // `[` or `]` inside the fragment ⇒ malformed / nested, bail.
        if after.contains("[") || after.contains("]") { return nil }
        // Past the name once a heading or alias separator is typed.
        if after.contains("#") || after.contains("|") { return nil }
        return String(after)
    }

    /// Workspace document names matching `partial` (case-insensitive prefix),
    /// sorted, de-duplicated, with an exact full match dropped (nothing left to
    /// complete). An empty `partial` returns every candidate.
    public static func completions(forPartial partial: String, candidates: [String]) -> [String] {
        let p = partial.lowercased()
        var seen = Set<String>()
        let matched = candidates.filter { name in
            let low = name.lowercased()
            guard low != p else { return false }
            guard p.isEmpty || low.hasPrefix(p) else { return false }
            return seen.insert(low).inserted
        }
        return matched.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
