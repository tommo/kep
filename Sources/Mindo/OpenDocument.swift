import Foundation
import MindoBase
import MindoCore
import MindoMindMap
import MindoModel

/// One row in the App's open-tabs list. Wraps the actual document payload
/// (`Kind`) plus the metadata the tab bar / file watcher need.
struct OpenDocument: Identifiable, Hashable {
    enum Kind {
        case mindMap(MindMap)
        case text(String, fileType: SupportedFileType?)
        case unsupported(String)

        var preferredExtension: String? {
            switch self {
            case .mindMap: return "mmd"
            case .text(_, let t): return t?.rawValue
            case .unsupported: return nil
            }
        }
    }

    let id = UUID()
    var kind: Kind
    var fileURL: URL?
    var title: String
    /// Set when the file watcher detected an external write since we last
    /// reloaded. UI shows an orange dot on the tab.
    var hasExternalChanges: Bool = false
    /// Set when the editor has accepted user edits since the last save /
    /// load. Used by the external-change conflict dialog so we only prompt
    /// when there's actually unsaved local work to protect.
    var isDirty: Bool = false

    static func load(from url: URL) throws -> OpenDocument {
        let title = url.lastPathComponent
        let type = SupportedFileType.classify(url: url)
        switch type {
        case .mindMap:
            let text = try String(contentsOf: url, encoding: .utf8)
            let map: MindMap
            if let parsed = try? MindMap(text: text) {
                map = parsed
            } else {
                // Empty or non-.mmd content (e.g. an agent-created stub written
                // as plain text): open a usable map instead of failing to open.
                // Seed the root from the filename and keep any text as children
                // so nothing is lost.
                let m = MindMap()
                let root = Topic(text: url.deletingPathExtension().lastPathComponent)
                for line in text.split(separator: "\n") {
                    let t = line.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { _ = root.addChild(text: t) }
                }
                m.root = root
                map = m
            }
            return OpenDocument(kind: .mindMap(map), fileURL: url, title: title)
        case .markdown, .plantUML, .csv, .plainText:
            let text = try String(contentsOf: url, encoding: .utf8)
            return OpenDocument(kind: .text(text, fileType: type), fileURL: url, title: title)
        case .jpeg, .png, .none:
            return OpenDocument(kind: .unsupported(url.path), fileURL: url, title: title)
        }
    }

    /// Convenience flag — true for any document whose kind is .mindMap.
    var isMindMap: Bool {
        if case .mindMap = kind { return true }
        return false
    }

    /// True for kinds whose contents can round-trip through `save(to:)`.
    /// `.unsupported` (binary blob references) is excluded.
    var isAutosavable: Bool {
        if case .unsupported = kind { return false }
        return true
    }

    /// Outline rows derived from this document's content. Each Kind picks
    /// the appropriate extractor; unsupported / unknown text returns empty.
    var outlineItems: [OutlineItem] {
        switch kind {
        case .mindMap(let map): return Outline.fromMindMap(map)
        case .text(let body, .markdown), .text(let body, .plantUML):
            return Outline.fromMarkdown(body)
        case .text, .unsupported: return []
        }
    }

    func save(to url: URL) throws {
        switch kind {
        case .mindMap(let map):
            try map.write().write(to: url, atomically: true, encoding: .utf8)
        case .text(let s, _):
            try s.write(to: url, atomically: true, encoding: .utf8)
        case .unsupported:
            break
        }
    }

    static func == (lhs: OpenDocument, rhs: OpenDocument) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One of the bundled mindmap themes (Light / Dark / Classic). Persisted as
/// a `String` so it round-trips through UserDefaults cleanly.
enum ThemeChoice: String, CaseIterable, Hashable {
    case light, dark, classic
    var theme: MindMapTheme {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .classic: return .classic
        }
    }
}
