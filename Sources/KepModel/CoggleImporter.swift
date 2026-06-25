import Foundation

/// Reads Coggle `.mm` exports — FreeMind-flavored XML with one Coggle
/// quirk: topic text often embeds Markdown links / images. We delegate
/// the structural parse to `FreemindImporter` (the `<map><node TEXT=…>`
/// shape is identical) and then walk the topic tree to extract:
///
/// - The first `[label](url)` link → moved to an `ExtraLink`, the label
///   becomes the topic's plain text.
/// - The first `![alt](imageUrl)` markdown image → moved to the
///   `mmd.image` attribute when `imageUrl` is a `data:` URL (the
///   built-in renderer expects base64, not a remote URL). External URLs
///   are stripped out of the topic text without trying to fetch them.
public enum CoggleImporter {

    public enum ImportError: Error, LocalizedError {
        case invalidXML(String)
        case noRootNode

        public var errorDescription: String? {
            switch self {
            case .invalidXML(let msg): return "Invalid Coggle XML: \(msg)"
            case .noRootNode: return "Coggle file has no root <node>"
            }
        }
    }

    public static func parse(_ xml: String) throws -> MindMap {
        // Reuse FreemindImporter for the structural walk. Map its errors so
        // the surface error type stays Coggle-specific (callers that present
        // Coggle file picker won't see "Invalid FreeMind XML").
        do {
            let map = try FreemindImporter.parse(xml)
            map.root?.traverse { extractMarkdownLinks(in: $0) }
            return map
        } catch FreemindImporter.ImportError.invalidXML(let msg) {
            throw ImportError.invalidXML(msg)
        } catch FreemindImporter.ImportError.noRootNode {
            throw ImportError.noRootNode
        }
    }

    /// Pull markdown links / images out of the topic's text and route them
    /// to ExtraLink / mmd.image. Mutates the topic in place.
    static func extractMarkdownLinks(in topic: Topic) {
        var text = topic.text
        if let (alt, url, range) = firstImageMatch(in: text) {
            // Only data: URLs round-trip cleanly into the renderer; others
            // are recorded as a link but the image bytes aren't fetched.
            if url.hasPrefix("data:") {
                let comma = url.firstIndex(of: ",")
                if let comma = comma {
                    let base64 = String(url[url.index(after: comma)...])
                    topic.setAttribute(TopicAttribute.image, base64)
                }
            } else {
                topic.setExtra(ExtraLink(uri: url))
            }
            text.replaceSubrange(range, with: alt.isEmpty ? "" : alt)
        }
        if let (label, url, range) = firstLinkMatch(in: text) {
            topic.setExtra(ExtraLink(uri: url))
            text.replaceSubrange(range, with: label)
        }
        topic.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// First `[label](url)` link in the string, returning label, url, and
    /// the range that should be replaced. Skips `![…](…)` image syntax.
    static func firstLinkMatch(in s: String) -> (label: String, url: String, range: Range<String.Index>)? {
        return matchMarkdownLink(in: s, image: false)
    }

    /// First `![alt](url)` image. Same shape as `firstLinkMatch` for callers.
    static func firstImageMatch(in s: String) -> (alt: String, url: String, range: Range<String.Index>)? {
        return matchMarkdownLink(in: s, image: true)
    }

    /// Shared regex walker — image=true matches `![…](…)`, false matches
    /// `[…](…)` while skipping the image form.
    private static func matchMarkdownLink(in s: String, image: Bool) -> (String, String, Range<String.Index>)? {
        let pattern = image ? #"!\[([^\]]*)\]\(([^)]+)\)"# : #"(?<!!)\[([^\]]+)\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsRange = NSRange(s.startIndex..<s.endIndex, in: s)
        guard let match = regex.firstMatch(in: s, options: [], range: nsRange),
              match.numberOfRanges >= 3,
              let labelRange = Range(match.range(at: 1), in: s),
              let urlRange = Range(match.range(at: 2), in: s),
              let fullRange = Range(match.range, in: s) else {
            return nil
        }
        return (String(s[labelRange]), String(s[urlRange]), fullRange)
    }
}
