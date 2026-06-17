import Foundation

/// Rewrites `[[wiki links]]` into ordinary Markdown links with a custom
/// `mindo-wiki:` scheme, so the Markdown renderer turns them into `<a>` anchors
/// the preview can intercept (resolve → open the target doc). Pure/testable;
/// the WKWebView nav handler decodes the scheme back into (target, heading).
public enum WikiLinkMarkdown {
    public static let scheme = "mindo-wiki"

    /// Replace each cross-document `[[…]]` with `[display](mindo-wiki:Target#Heading)`.
    /// In-document links (`[[#Heading]]`, empty target) are left as-is.
    public static func linkify(_ markdown: String) -> String {
        let links = WikiLinkParser.links(in: markdown).filter { !$0.target.isEmpty }
        guard !links.isEmpty else { return markdown }
        let result = NSMutableString(string: markdown)
        // Replace right-to-left so earlier ranges stay valid.
        for link in links.sorted(by: { $0.nsRange.location > $1.nsRange.location }) {
            result.replaceCharacters(in: link.nsRange, with: replacement(for: link))
        }
        return result as String
    }

    /// Decode a `mindo-wiki:` URL string back into (target, heading?). Used by
    /// the preview click handler.
    public static func decode(_ urlString: String) -> (target: String, heading: String?)? {
        guard urlString.hasPrefix("\(scheme):") else { return nil }
        let rest = String(urlString.dropFirst(scheme.count + 1))
        let parts = rest.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let target = parts[0].removingPercentEncoding ?? String(parts[0])
        let heading = parts.count > 1 ? (parts[1].removingPercentEncoding ?? String(parts[1])) : nil
        return target.isEmpty ? nil : (target, heading?.isEmpty == true ? nil : heading)
    }

    private static func replacement(for link: WikiLink) -> String {
        let encTarget = link.target.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? link.target
        var url = "\(scheme):\(encTarget)"
        if let h = link.heading, !h.isEmpty {
            let encH = h.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? h
            url += "#\(encH)"
        }
        return "[\(escapeLinkText(link.displayText))](\(url))"
    }

    /// Escape characters that would break Markdown link-text `[...]`.
    private static func escapeLinkText(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "[", with: "\\[")
         .replacingOccurrences(of: "]", with: "\\]")
    }
}
