import Foundation
import MindoModel
import MindoScript

extension AppSession {

    /// Run a Lua script against the active mind map. On success the canvas
    /// reloads from the mutated model and the document is marked dirty. KB
    /// builtins (`resolve`/`backlinks`/`docs`) see the workspace corpus.
    @MainActor
    func runActiveLuaScript(_ source: String) -> ScriptRunResult {
        guard let id = activeDocumentID,
              let idx = openDocuments.firstIndex(where: { $0.id == id }),
              case .mindMap(let map) = openDocuments[idx].kind else {
            return ScriptRunResult(output: "", error: "Open a mind map to run a script against it.")
        }
        let (files, corpus) = workspaceCorpus()
        let before = map.write()
        let result = MindoScriptRunner.run(source, on: map, corpus: corpus, allFiles: files)
        if result.ok {
            // The whole script is one undoable step: snapshot the map before/after
            // and register a single coalesced undo (script mutations bypass the
            // canvas's per-edit undo path).
            registerMapSnapshotUndo(map, before: before, after: map.write(), name: "Run Script")
            openDocuments[idx].isDirty = true
            mindmapCommand = .reload   // rebuild the canvas from the mutated map
            mindmapCommandTick &+= 1
        }
        return result
    }

    /// Register a single undo step that swaps the mind map between two `.mmd`
    /// snapshots — used to make a whole script / agent run atomically undoable.
    /// No-op when nothing changed or there's no live canvas to host the undo.
    @MainActor
    func registerMapSnapshotUndo(_ map: MindMap, before: String, after: String, name: String) {
        guard before != after, let view = activeMindMapView else { return }
        func restore(_ mmd: String) {
            guard let parsed = try? MindMap(text: mmd), let root = parsed.root else { return }
            map.root = root
            root.traverse { $0.map = map }   // reattach the map backref across the tree
        }
        view.registerUndo(name: name,
                          forward: { restore(after) },
                          inverse: { restore(before) })
    }
}
