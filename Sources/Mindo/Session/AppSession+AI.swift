import Foundation
import MindoGenAI
import MindoModel
import MindoCore

extension AppSession {

    /// Per-intent prompt template + insertion mode preset. Mirrors the
    /// shape of mindolph's split AiInputPane / AiSummaryPane / AiReframePane.
    /// All three intents fan out to the same AIGeneratePane sheet so the
    /// streaming/insertion plumbing stays single-source.
    enum AIIntent { case input, summarize, reframe }

    /// Configure + open the AI generate sheet for the given intent. The
    /// "input" intent matches the previous one-button behavior — a free
    /// prompt with the doc-appropriate insertion modes. summarize and
    /// reframe seed the prompt + force append/replace as appropriate.
    func openAIGenerate(intent: AIIntent = .input) {
        guard let doc = activeDocument else { return }
        let modesForKind: [AIGeneratePane.InsertionMode]
        switch doc.kind {
        case .mindMap: modesForKind = [.childTopic]
        case .text:    modesForKind = [.append, .replace]
        case .unsupported: modesForKind = [.append, .replace]
        }
        switch intent {
        case .input:
            aiSupportedModes = modesForKind
            aiDefaultPrompt = defaultInputPrompt(for: doc)
        case .summarize:
            // Summary writes alongside the source — append for text docs,
            // childTopic for mindmaps.
            aiSupportedModes = doc.isMindMap ? [.childTopic] : [.append]
            aiDefaultPrompt = "Summarize the selected text in three concise bullet points."
        case .reframe:
            // Reframe rewrites the selection in place.
            aiSupportedModes = doc.isMindMap ? [.childTopic] : [.replace]
            aiDefaultPrompt = "Rewrite the selected text more clearly and concisely."
        }
        aiGenerateOpen = true
    }

    private func defaultInputPrompt(for doc: OpenDocument) -> String {
        switch doc.kind {
        case .mindMap:
            return "Generate three child topics for the selected node."
        case .text(_, .markdown):
            return "Continue the document below."
        case .text(_, .plantUML):
            return "Generate a PlantUML diagram source for: "
        default:
            return ""
        }
    }

    /// Whole-workspace context for the assistant: the list of documents and
    /// which one the user is viewing — but NOT any document's content. The
    /// assistant is workspace-wide, not tied to one doc; it fetches content on
    /// demand via the `read_document` tool (and mind-map tools).
    func aiWorkspaceContextBlock() -> String? {
        var parts: [String] = []
        let names = wikiLinkDocumentNames()
        if !names.isEmpty {
            parts.append("Workspace documents (fetch any with the read_document tool): "
                         + names.joined(separator: ", "))
        }
        if let doc = activeDocument {
            let kind: String
            switch doc.kind {
            case .mindMap: kind = "mind map"
            case .text(_, let t): kind = t?.rawValue ?? "document"
            case .unsupported: kind = "document"
            }
            parts.append("The user is currently viewing the \(kind) \"\(doc.title)\".")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    /// Context block handed to the conversational assistant before each send:
    /// what the user is currently editing, so replies are grounded in the doc.
    /// Body is truncated to keep the prompt cheap. Returns nil when no doc is open.
    func aiDialogContextBlock() -> String? {
        guard let doc = activeDocument else { return nil }
        let kind: String
        var body = ""
        switch doc.kind {
        case .mindMap(let map):
            kind = "mind map"
            body = map.root.map { Self.outline(of: $0) } ?? ""
        case .text(let text, let type):
            kind = type?.rawValue ?? "text"
            body = text
        case .unsupported:
            kind = "document"
        }
        let title = doc.title
        let truncated = body.count > 4000 ? String(body.prefix(4000)) + "\n…(truncated)" : body
        return """
        The user is currently editing a \(kind) titled "\(title)". Its current content:
        ---
        \(truncated)
        ---
        Answer questions and make edits in the context of this document.
        """
    }

    /// Flat outline of a mind map for context (root then indented children).
    private static func outline(of root: Topic, depth: Int = 0) -> String {
        let pad = String(repeating: "  ", count: depth)
        var out = pad + root.text + "\n"
        for child in root.children { out += outline(of: child, depth: depth + 1) }
        return out
    }

    /// Insert an assistant reply into the active document — append for text,
    /// child topics for a mind map (mirrors the AIGenerate insertion modes).
    func insertDialogReply(_ text: String) {
        guard let doc = activeDocument else { return }
        applyAIResult(text: text, mode: doc.isMindMap ? .childTopic : .append)
    }

    /// Apply a generated AI result to the active document. Markdown gets
    /// appended/replaced as text; mind map splits the output by line and
    /// adds each non-empty line as a child of the root.
    func applyAIResult(text: String, mode: AIGeneratePane.InsertionMode) {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }) else { return }
        var doc = openDocuments[idx]
        switch (doc.kind, mode) {
        case (.text(let body, let t), .append):
            doc.kind = .text(body + (body.hasSuffix("\n") ? "" : "\n") + text, fileType: t)
        case (.text(_, let t), .replace):
            doc.kind = .text(text, fileType: t)
        case (.mindMap(let map), .childTopic):
            appendLinesAsChildren(of: map, text: text)
        default:
            break
        }
        openDocuments[idx] = doc
    }
}
