import Foundation
import MindoGenAI
import MindoModel

extension AppSession {

    /// Configure + open the AI generate sheet, picking sensible defaults
    /// (insertion modes, prompt) based on the active doc's type.
    func openAIGenerate() {
        guard let doc = activeDocument else { return }
        switch doc.kind {
        case .mindMap:
            aiSupportedModes = [.childTopic]
            aiDefaultPrompt = "Generate three child topics for the selected node."
        case .text(_, .markdown):
            aiSupportedModes = [.append, .replace]
            aiDefaultPrompt = "Continue the document below."
        case .text(_, .plantUML):
            aiSupportedModes = [.append, .replace]
            aiDefaultPrompt = "Generate a PlantUML diagram source for: "
        default:
            aiSupportedModes = [.append, .replace]
            aiDefaultPrompt = ""
        }
        aiGenerateOpen = true
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
