import AppKit
import Foundation

/// Helpers that decide whether a pasteboard's plain-text payload looks
/// like a URL — used by the markdown editor's smart-paste-as-link rule.
/// Lives outside the NSTextView so the URL detection can be unit-tested
/// without a real pasteboard fixture.
public enum MarkdownPasteRule {

    /// Prefixes that count as "this is a URL" for the wrap-as-link path.
    /// Conservative on purpose: bare "www.example.com" without a scheme
    /// is *not* a URL here — most editors that try to be clever about
    /// schemeless URLs end up wrapping plain text the user wanted to paste.
    static let urlSchemes = ["http://", "https://", "ftp://", "mailto:"]

    /// Read the pasteboard's plain-text payload and return it iff it
    /// looks like a single URL (one line, starts with a recognized
    /// scheme, no embedded whitespace).
    public static func urlFromPasteboard(_ pasteboard: NSPasteboard) -> String? {
        guard let raw = pasteboard.string(forType: .string) else { return nil }
        return urlIfMatched(raw)
    }

    /// Pure-logic counterpart used by tests. Trims surrounding whitespace,
    /// rejects multi-line payloads + payloads that contain spaces (those
    /// almost always mean "the user meant to paste plain text").
    public static func urlIfMatched(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: { $0.isNewline || $0 == " " }) else { return nil }
        let lower = trimmed.lowercased()
        for scheme in urlSchemes where lower.hasPrefix(scheme) {
            return trimmed
        }
        return nil
    }
}
