import AppKit
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
    var activeIsMarkdown: Bool { activeFileType == .markdown }

    /// True when at least one open document is dirty AND has a file URL
    /// (so Save All has something it can actually flush; untitled docs
    /// are skipped by saveAllDirty for UX reasons — see that method).
    var hasDirtyOpenDocuments: Bool {
        openDocuments.contains { $0.isDirty && $0.fileURL != nil }
    }

    var activeFileType: SupportedFileType? {
        guard let doc = activeDocument else { return nil }
        switch doc.kind {
        case .mindMap: return .mindMap
        case .text(_, let t): return t
        case .unsupported: return nil
        }
    }

    /// Route ⌘F to the appropriate Find affordance for the active doc:
    /// mindmap → toggles the in-document find bar overlay; text editors
    /// (markdown / plantuml / csv) → invokes NSTextView's built-in find
    /// bar via the standard NSTextFinderClient action.
    @MainActor
    func invokeFindInActiveDocument() {
        guard let doc = activeDocument else { return }
        switch doc.kind {
        case .mindMap:
            inDocFindOpen.toggle()
        case .text, .unsupported:
            // Route performFindPanelAction: through the responder chain so
            // NSTextView's built-in find bar (usesFindBar=true) takes over.
            // The sender MUST carry tag = showFindPanel — performFindPanelAction
            // reads sender.tag to pick the operation, and the old nil sender's
            // tag-0 was an invalid action, so ⌘F silently did nothing.
            TextFindBar.showFindBar()
        }
    }

    // MARK: - Snippets

    func insertSnippet(_ snippet: Snippet) {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        let expanded = SnippetExpander.expand(snippet.body, context: snippetContext(for: openDocuments[idx]))
        switch openDocuments[idx].kind {
        case .text(let body, let t):
            let glue = body.hasSuffix("\n") || body.isEmpty ? "" : "\n"
            openDocuments[idx].kind = .text(body + glue + expanded, fileType: t)
        case .mindMap(let map):
            appendLinesAsChildren(of: map, text: expanded)
        case .unsupported:
            break
        }
    }

    /// Build the per-doc context that `${filename}` and `${title}` need.
    private func snippetContext(for doc: OpenDocument) -> SnippetExpander.Context {
        let filename = doc.fileURL?.deletingPathExtension().lastPathComponent ?? ""
        var title = ""
        if case .mindMap(let map) = doc.kind { title = map.root?.text ?? "" }
        return SnippetExpander.Context(filename: filename, title: title)
    }

    /// Split `text` by line and add each non-empty line as a child of the
    /// map's root, creating the root if missing. Shared by snippet insertion
    /// and AI childTopic generation.
    func appendLinesAsChildren(of map: MindMap, text: String) {
        let parent = map.root ?? Topic(text: "Root")
        if map.root == nil { map.root = parent }
        for line in text.split(whereSeparator: { $0 == "\n" }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            _ = parent.addChild(text: trimmed)
        }
    }
}
