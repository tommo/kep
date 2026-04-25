import Foundation
import MindoGenAI
import MindoModel

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
