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
        guard let content = zip.data(for: "content.json")
                ?? zip.firstData(where: { $0.lowercased().hasSuffix("content.json") }) else {
            // Distinguish "it's the old XML format" from "no content at all".
            if zip.firstData(where: { $0.lowercased().hasSuffix("content.xml") }) != nil {
                throw ImportError.legacyUnsupported
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
