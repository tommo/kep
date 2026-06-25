import Foundation

/// Pure helpers for the "convert topic → parent note / link" context actions
/// (javamind parity with ConvertTopicExtension). Kept free of AppKit/undo so
/// the URI test and note-merge rules are unit-testable.
public enum TopicConvert {

    /// True when `text` is a single-token absolute URI suitable for an
    /// `ExtraLink` — requires an explicit scheme (so plain words / sentences
    /// don't qualify) and either a host or a scheme that has none (mailto).
    public static func isLinkURI(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(where: { $0.isWhitespace }) else { return false }
        guard let url = URL(string: t), let scheme = url.scheme, !scheme.isEmpty else { return false }
        if url.host?.isEmpty == false { return true }
        // Schemes that legitimately carry no host.
        return ["mailto", "tel", "file"].contains(scheme.lowercased())
    }

    /// The parent's note after folding in a converted child's text — appended
    /// on its own line, or used as-is when the parent had no note.
    public static func mergedNoteText(existing: String?, adding: String) -> String {
        let add = adding.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let existing, !existing.isEmpty else { return add }
        return existing + "\n" + add
    }
}
