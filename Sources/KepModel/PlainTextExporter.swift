import Foundation

/// Indented bullet-list rendering of a topic tree. Useful for "export
/// branch as plain text" — every depth level adds 2 spaces, and each
/// topic prefixes with `- `. Headlines collapse newlines to spaces so
/// the bullet structure stays single-line per entry.
public enum PlainTextExporter {
    public static func export(_ map: MindMap) -> String {
        var out = ""
        if let root = map.root {
            write(root, depth: 0, into: &out)
        }
        return out
    }

    private static func write(_ topic: Topic, depth: Int, into out: inout String) {
        let indent = String(repeating: "  ", count: depth)
        out.append("\(indent)- \(escape(topic.text))\n")
        for child in topic.children {
            write(child, depth: depth + 1, into: &out)
        }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ")
    }
}
