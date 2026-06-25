import Foundation

/// Serializes a `MindMap` back to FreeMind / Freeplane `.mm` XML so the user
/// can hand the file to a FreeMind-only collaborator. The shape mirrors what
/// `FreemindImporter` accepts, so an `import → export → import` round-trip
/// preserves text, folding, side, edge attrs, and BUILTIN icons.
public enum FreemindExporter {

    /// Build the .mm XML document for `map`. Result is the full `<?xml ?>`
    /// + `<map>` + recursive `<node>` tree, suitable for writing to disk.
    public static func export(_ map: MindMap) -> String {
        var out = ""
        out.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        out.append("<map version=\"1.0.1\">\n")
        if let root = map.root {
            writeNode(root, indent: "  ", into: &out)
        }
        out.append("</map>\n")
        return out
    }

    private static func writeNode(_ topic: Topic, indent: String, into out: inout String) {
        // Open <node …> with attributes that mirror what the importer reads.
        out.append(indent)
        out.append("<node TEXT=\"")
        out.append(escape(topic.text))
        out.append("\"")
        if topic.attribute(TopicAttribute.collapsed) == "true" {
            out.append(" FOLDED=\"true\"")
        }
        if topic.attribute(TopicAttribute.leftSide) == "true" {
            out.append(" POSITION=\"left\"")
        }
        // Self-close when the node has no children, no edge attrs, no icon.
        let hasEdge = topic.attribute(TopicAttribute.edgeColor) != nil
                   || topic.attribute(TopicAttribute.edgeStyle) != nil
                   || topic.attribute(TopicAttribute.edgeWidth) != nil
        let hasIcon = topic.attribute(TopicAttribute.emoticon) != nil
        if topic.children.isEmpty && !hasEdge && !hasIcon {
            out.append("/>\n")
            return
        }
        out.append(">\n")

        let childIndent = indent + "  "
        if hasEdge {
            out.append(childIndent)
            out.append("<edge")
            if let c = topic.attribute(TopicAttribute.edgeColor) { out.append(" COLOR=\"\(escape(c))\"") }
            if let s = topic.attribute(TopicAttribute.edgeStyle) { out.append(" STYLE=\"\(escape(s))\"") }
            if let w = topic.attribute(TopicAttribute.edgeWidth) { out.append(" WIDTH=\"\(escape(w))\"") }
            out.append("/>\n")
        }
        if let icon = topic.attribute(TopicAttribute.emoticon) {
            out.append(childIndent)
            out.append("<icon BUILTIN=\"\(escape(icon))\"/>\n")
        }
        for child in topic.children {
            writeNode(child, indent: childIndent, into: &out)
        }
        out.append(indent)
        out.append("</node>\n")
    }

    /// XML attribute-value escape — &, <, >, ", ' all need the entity form.
    private static func escape(_ s: String) -> String {
        ModelUtils.escapeXML(s, quotes: true)
    }
}
