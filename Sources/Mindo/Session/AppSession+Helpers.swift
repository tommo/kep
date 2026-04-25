import Foundation
import MindoBase
import MindoCore
import MindoModel

extension AppSession {

    // MARK: - Active document

    /// Lookup helper — the document identified by `activeDocumentID`, if any.
    var activeDocument: OpenDocument? {
        guard let id = activeDocumentID else { return nil }
        return openDocuments.first { $0.id == id }
    }

    // MARK: - Outline navigation

    /// Push a navigation target into the active editor. Tags the value with a
    /// trailing UUID so two clicks on the same outline row re-fire — the
    /// editor coordinator only acts on string change.
    func requestOutlineNavigation(target: String) {
        outlineNavigationTarget = "\(target)#\(UUID().uuidString)"
    }

    /// Strip the disambiguation suffix the active editor was passed.
    var sanitizedNavigationTarget: String? {
        guard let target = outlineNavigationTarget else { return nil }
        return target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
    }

    // MARK: - Active doc accessors

    /// True when the active document is a markdown text doc (powers Export menu enabling).
    var activeIsMarkdown: Bool {
        guard let doc = activeDocument else { return false }
        if case .text(_, .markdown) = doc.kind { return true }
        return false
    }

    var activeFileType: SupportedFileType? {
        guard let doc = activeDocument else { return nil }
        switch doc.kind {
        case .mindMap: return .mindMap
        case .text(_, let t): return t
        case .unsupported: return nil
        }
    }

    // MARK: - Snippets

    func insertSnippet(_ snippet: Snippet) {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        switch openDocuments[idx].kind {
        case .text(let body, let t):
            let glue = body.hasSuffix("\n") || body.isEmpty ? "" : "\n"
            openDocuments[idx].kind = .text(body + glue + snippet.body, fileType: t)
        case .mindMap(let map):
            let parent = map.root ?? Topic(text: "Root")
            if map.root == nil { map.root = parent }
            for line in snippet.body.split(whereSeparator: { $0 == "\n" }) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                _ = parent.addChild(text: trimmed)
            }
        case .unsupported:
            break
        }
    }
}
