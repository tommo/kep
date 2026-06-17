import Foundation

/// Imports Novamind `.nm5` files. A `.nm5` is a ZIP bundle whose `content.xml`
/// holds (1) a `<topics>` table of content topics keyed by id (rich text +
/// notes) and (2) a `<maps><map>` tree of `<topic-node topic-ref=…>` that
/// references those content topics and nests via `<sub-topics>`. We resolve the
/// tree against the content table, mapping topic notes → `ExtraNote`, per-node
/// fill/line styles → fillColor/borderColor, and `<link-lines>` between
/// topic-nodes → `ExtraTopic` jump-links. Mirrors javamind's
/// Novamind2MindMapImporter.
public enum NovamindImporter {
    public enum ImportError: Error, LocalizedError {
        case notAZip, noContent, emptyDocument
        public var errorDescription: String? {
            switch self {
            case .notAZip: return "Not a valid .nm5 file (not a ZIP archive)."
            case .noContent: return "No content.xml found in the .nm5 bundle."
            case .emptyDocument: return "The .nm5 file has no map/topics."
            }
        }
    }

    public static func parse(data: Data) throws -> MindMap {
        guard let zip = ZipArchive(data: data) else { throw ImportError.notAZip }
        guard let contentData = zip.data(for: "content.xml")
                ?? zip.firstData(where: { $0.lowercased().hasSuffix("content.xml") }) else {
            throw ImportError.noContent
        }
        let doc = try XMLDocument(data: contentData)
        guard let root = doc.rootElement(), root.name == "document" else { throw ImportError.emptyDocument }

        // 1. Content topics, keyed by id → (title text, optional notes).
        var content: [String: (text: String, notes: String?)] = [:]
        for topicsEl in root.elements(forName: "topics") {
            for t in topicsEl.elements(forName: "topic") {
                guard let id = t.attribute(forName: "id")?.stringValue else { continue }
                content[id] = (text: richTextString(directlyIn: t), notes: notesString(of: t))
            }
        }

        // 2. The tree: maps → first map → root topic-node, nested via sub-topics.
        guard let maps = root.elements(forName: "maps").first,
              let firstMap = maps.elements(forName: "map").first,
              let rootNode = firstMap.elements(forName: "topic-node").first else {
            throw ImportError.emptyDocument
        }
        let map = MindMap()
        let rootTopic = Topic(text: "")
        map.root = rootTopic
        var nodeToTopic: [String: Topic] = [:]
        apply(node: rootNode, to: rootTopic, content: content, nodeMap: &nodeToTopic)
        if rootTopic.text.isEmpty { rootTopic.text = "Novamind Map" }

        wireJumpLinks(in: firstMap, nodeToTopic: nodeToTopic)
        return map
    }

    // MARK: - Tree

    private static func apply(node: XMLElement, to topic: Topic,
                              content: [String: (text: String, notes: String?)],
                              nodeMap: inout [String: Topic]) {
        if let nodeId = node.attribute(forName: "id")?.stringValue { nodeMap[nodeId] = topic }
        if let ref = node.attribute(forName: "topic-ref")?.stringValue, let c = content[ref] {
            topic.text = c.text
            if let notes = c.notes { topic.setExtra(ExtraNote(text: notes)) }
        }
        applyStyleColors(from: node, to: topic)
        if let sub = node.elements(forName: "sub-topics").first {
            for childNode in sub.elements(forName: "topic-node") {
                let child = topic.addChild(text: "")
                apply(node: childNode, to: child, content: content, nodeMap: &nodeMap)
            }
        }
    }

    // MARK: - Styles

    /// `<topic-node-view><topic-node-style><fill-style><solid-color color=…>` →
    /// fillColor; `<line-style color=…>` → borderColor.
    private static func applyStyleColors(from node: XMLElement, to topic: Topic) {
        guard let view = node.elements(forName: "topic-node-view").first,
              let style = view.elements(forName: "topic-node-style").first else { return }
        if let fill = style.elements(forName: "fill-style").first,
           let solid = fill.elements(forName: "solid-color").first,
           let hex = normalizedHex(solid.attribute(forName: "color")?.stringValue) {
            topic.setAttribute(TopicAttribute.fillColor, hex)
        }
        if let line = style.elements(forName: "line-style").first,
           let hex = normalizedHex(line.attribute(forName: "color")?.stringValue) {
            topic.setAttribute(TopicAttribute.borderColor, hex)
        }
    }

    /// Accept `#RRGGBB`, `RRGGBB`, or `#RRGGBBAA`/`RRGGBBAA`; return `#RRGGBB`.
    private static func normalizedHex(_ raw: String?) -> String? {
        guard var s = raw?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, s.allSatisfy({ $0.isHexDigit }) else { return nil }
        return "#" + s.prefix(6)
    }

    // MARK: - Jump links

    /// `<link-lines><topic-node><link-line-data start-…-ref end-…-ref>` →
    /// ExtraTopic from the start node's topic to the end node's topic.
    private static func wireJumpLinks(in firstMap: XMLElement, nodeToTopic: [String: Topic]) {
        for lines in firstMap.elements(forName: "link-lines") {
            for tn in lines.elements(forName: "topic-node") {
                for lld in tn.elements(forName: "link-line-data") {
                    guard let startRef = lld.attribute(forName: "start-topic-node-ref")?.stringValue,
                          let endRef = lld.attribute(forName: "end-topic-node-ref")?.stringValue,
                          let from = nodeToTopic[startRef], let to = nodeToTopic[endRef],
                          from !== to else { continue }
                    var uid = to.attribute(ExtraTopic.topicUidAttr)
                    if uid == nil { let g = UUID().uuidString; to.setAttribute(ExtraTopic.topicUidAttr, g); uid = g }
                    from.setExtra(ExtraTopic(topicUID: uid!))
                }
            }
        }
    }

    // MARK: - Rich text

    /// Concatenated text of every `<rich-text>` directly under `element`.
    private static func richTextString(directlyIn element: XMLElement) -> String {
        element.elements(forName: "rich-text").map(runsText).joined()
    }

    /// `<rich-text><text-run>…</text-run></rich-text>` → plain text; `<br>` → \n.
    private static func runsText(_ richText: XMLElement) -> String {
        var s = ""
        for run in richText.elements(forName: "text-run") {
            for child in run.children ?? [] {
                if let el = child as? XMLElement, el.name == "br" { s += "\n" }
                else { s += child.stringValue ?? "" }
            }
        }
        return s
    }

    private static func notesString(of topic: XMLElement) -> String? {
        var out = ""
        for notes in topic.elements(forName: "notes") {
            out += notes.elements(forName: "rich-text").map(runsText).joined()
        }
        return out.isEmpty ? nil : out
    }
}
