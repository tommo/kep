import Foundation

/// Imports Novamind `.nm5` files. A `.nm5` is a ZIP bundle whose `content.xml`
/// holds (1) a `<topics>` table of content topics keyed by id (rich text +
/// notes) and (2) a `<maps><map>` tree of `<topic-node topic-ref=…>` that
/// references those content topics and nests via `<sub-topics>`. We resolve the
/// tree against the content table, mapping topic notes → `ExtraNote`. Mirrors
/// javamind's Novamind2MindMapImporter (tree + text + notes; jump-links between
/// topics are a possible follow-up).
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
        apply(node: rootNode, to: rootTopic, content: content)
        if rootTopic.text.isEmpty { rootTopic.text = "Novamind Map" }
        return map
    }

    // MARK: - Tree

    private static func apply(node: XMLElement, to topic: Topic,
                              content: [String: (text: String, notes: String?)]) {
        if let ref = node.attribute(forName: "topic-ref")?.stringValue, let c = content[ref] {
            topic.text = c.text
            if let notes = c.notes { topic.setExtra(ExtraNote(text: notes)) }
        }
        if let sub = node.elements(forName: "sub-topics").first {
            for childNode in sub.elements(forName: "topic-node") {
                let child = topic.addChild(text: "")
                apply(node: childNode, to: child, content: content)
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
