import Foundation
import MindoModel
import MindoMarkdown
import MindoScript

/// Bridges the Research Notebook editor's injected run closures to the
/// MindoScript Lua kernel. Lives in the app target (which imports both
/// MindoMarkdown and MindoScript) so MindoMarkdown stays free of a scripting
/// dependency — same pattern as the CSV agent-tool injection.
extension AppSession {

    /// Run every code cell against ONE shared kernel (globals persist across
    /// cells), persist the outputs sidecar, return the full map.
    @MainActor
    func runNotebookAll(_ notebook: Notebook, in ctx: NotebookRunContext) async -> ExecOutputs {
        let (files, corpus) = workspaceCorpus()
        var outputs = ctx.documentURL.map { ExecOutputsStore.load(for: $0) } ?? ExecOutputs()
        // Scratch map: notebook Lua can read the KB (corpus/files) and compute;
        // map mutations stay scratch-only so the user's open mind map is never
        // touched. (Follow-up: opt-in run against the active map with undo.)
        guard let kernel = try? MindoNotebookKernel(map: MindMap(), corpus: corpus, allFiles: files) else {
            return outputs
        }
        var live = Set<String>()
        for case .code(_, _, let code) in notebook.cells {
            let result = kernel.run(code)
            let hash = MarkdownExecBlocks.hash(code)
            outputs.set(ExecOutput(text: result.output, error: result.error), forHash: hash)
            live.insert(hash)
        }
        outputs.prune(keeping: live)
        if let url = ctx.documentURL { try? ExecOutputsStore.save(outputs, for: url) }
        return outputs
    }

    /// Run a single cell in a fresh kernel; load-modify-save the sidecar so a
    /// one-cell run doesn't drop sibling outputs.
    @MainActor
    func runNotebookCell(_ source: String, in ctx: NotebookRunContext) async -> ExecOutput {
        let (files, corpus) = workspaceCorpus()
        let result = (try? MindoNotebookKernel(map: MindMap(), corpus: corpus, allFiles: files))?.run(source)
            ?? ScriptRunResult(output: "", error: "executor unavailable")
        let out = ExecOutput(text: result.output, error: result.error)
        if let url = ctx.documentURL {
            var store = ExecOutputsStore.load(for: url)
            store.set(out, forHash: MarkdownExecBlocks.hash(source))
            try? ExecOutputsStore.save(store, for: url)
        }
        return out
    }
}
