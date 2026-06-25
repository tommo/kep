import Foundation

/// Imports modern XMind (Zen) `.xmind` files. A `.xmind` is a ZIP bundle whose
/// `content.json` holds an array of sheets; each sheet's `rootTopic` is a tree
/// of `{ title, notes, children: { attached: [...] } }`. We import the first
/// sheet. Topic notes map to `ExtraNote`. Legacy XMind 8 (`content.xml`) is not
/// yet supported — it surfaces a clear error.
public enum XMindImporter {
    public enum ImportError: Error, LocalizedError {
        case notAZip
        case noContent
        case legacyUnsupported
        case emptyDocument
        public var errorDescription: String? {
            switch self {
            case .notAZip: return "Not a valid .xmind file (not a ZIP archive)."
            case .noContent: return "No content.json found in the .xmind bundle."
            case .legacyUnsupported: return "Legacy XMind 8 files (content.xml) aren't supported yet — re-save as XMind Zen."
            case .emptyDocument: return "The .xmind file has no sheets/topics."
            }
        }
    }

    public static func parse(data: Data) throws -> MindMap {
        guard let zip = ZipArchive(data: data) else { throw ImportError.notAZip }
        // Modern Zen bundles carry content.json; legacy XMind 8 carries content.xml.
        guard let content = zip.data(for: "content.json")
                ?? zip.firstData(where: { $0.lowercased().hasSuffix("content.json") }) else {
            if let xml = zip.data(for: "content.xml")
                ?? zip.firstData(where: { $0.lowercased().hasSuffix("content.xml") }) {
                return try parseLegacyXML(xml)
            }
            throw ImportError.noContent
        }
        let json = try JSONSerialization.jsonObject(with: content)
        guard let sheets = json as? [[String: Any]], let sheet = sheets.first,
              let rootDict = sheet["rootTopic"] as? [String: Any] else {
            throw ImportError.emptyDocument
        }
        let map = MindMap()
        let root = Topic(text: title(of: rootDict, fallback: "Central Topic"))
        map.root = root
        applyNote(rootDict, to: root)
        buildChildren(of: rootDict, under: root)
        return map
    }

    // MARK: - Legacy XMind 8 (content.xml)

    /// `<xmap-content><sheet><topic><title>… + <children><topics><topic>…`.
    private static func parseLegacyXML(_ data: Data) throws -> MindMap {
        let doc = try XMLDocument(data: data)
        guard let root = doc.rootElement(),
              let sheet = root.elements(forName: "sheet").first,
              let rootTopic = sheet.elements(forName: "topic").first else {
            throw ImportError.emptyDocument
        }
        let map = MindMap()
        let topic = Topic(text: "")
        map.root = topic
        applyLegacy(element: rootTopic, to: topic)
        if topic.text.isEmpty { topic.text = "Central Topic" }
        return map
    }

    private static func applyLegacy(element: XMLElement, to topic: Topic) {
        topic.text = element.elements(forName: "title").first?.stringValue ?? ""
        if let note = legacyNote(element) { topic.setExtra(ExtraNote(text: note)) }
        for childTopic in legacyChildTopics(element) {
            applyLegacy(element: childTopic, to: topic.addChild(text: ""))
        }
    }

    /// `<children><topics><topic>` — XMind groups children under typed `<topics>`.
    private static func legacyChildTopics(_ topic: XMLElement) -> [XMLElement] {
        topic.elements(forName: "children")
            .flatMap { $0.elements(forName: "topics") }
            .flatMap { $0.elements(forName: "topic") }
    }

    private static func legacyNote(_ topic: XMLElement) -> String? {
        for notes in topic.elements(forName: "notes") {
            if let plain = notes.elements(forName: "plain").first?.stringValue, !plain.isEmpty { return plain }
            if let html = notes.elements(forName: "html").first?.stringValue, !html.isEmpty { return html }
        }
        return nil
    }

    // MARK: - Helpers

    private static func title(of dict: [String: Any], fallback: String) -> String {
        let t = (dict["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? fallback : t
    }

    private static func applyNote(_ dict: [String: Any], to topic: Topic) {
        if let notes = dict["notes"] as? [String: Any],
           let plain = notes["plain"] as? [String: Any],
           let content = plain["content"] as? String,
           !content.isEmpty {
            topic.setExtra(ExtraNote(text: content))
        }
    }

    private static func buildChildren(of dict: [String: Any], under parent: Topic) {
        guard let children = dict["children"] as? [String: Any] else { return }
        // XMind groups children by relationship; "attached" is the main tree.
        // Fall back to "detached" so free-floating topics aren't lost.
        let groups = (children["attached"] as? [[String: Any]] ?? [])
            + (children["detached"] as? [[String: Any]] ?? [])
        for childDict in groups {
            let child = parent.addChild(text: title(of: childDict, fallback: ""))
            applyNote(childDict, to: child)
            buildChildren(of: childDict, under: child)
        }
    }
}
