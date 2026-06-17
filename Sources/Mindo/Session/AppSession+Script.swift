import Foundation
import MindoModel
import MindoScript

extension AppSession {

    /// Run a Lua script against the active mind map. On success the canvas
    /// reloads from the mutated model and the document is marked dirty. KB
    /// builtins (`resolve`/`backlinks`/`docs`) see the workspace corpus.
    func runActiveLuaScript(_ source: String) -> ScriptRunResult {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }),
              case .mindMap(let map) = openDocuments[idx].kind else {
            return ScriptRunResult(output: "", error: "Open a mind map to run a script against it.")
        }
        let files = quickSwitcherFiles().map(\.url)
        // Best-effort KB corpus (text of workspace files) for backlinks/resolve.
        let corpus: [(url: URL, text: String)] = files.compactMap { url in
            (try? String(contentsOf: url, encoding: .utf8)).map { (url, $0) }
        }
        let result = MindoScriptRunner.run(source, on: map, corpus: corpus, allFiles: files)
        if result.ok {
            openDocuments[idx].isDirty = true
            mindmapCommand = .reload   // rebuild the canvas from the mutated map
            mindmapCommandTick &+= 1
        }
        return result
    }
}
