import Foundation
import MindoModel
import MindoMarkdown
import MindoScript
import MindoGenAI

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

    /// The agentic core: research `question` over the knowledge base and author
    /// findings (prose) + queries (code cells, run) INTO the notebook `sink`.
    /// Records authored cells during the loop, then applies them on the main
    /// actor afterwards (avoids touching the @MainActor sink mid-loop).
    @MainActor
    func runNotebookAgent(_ question: String, into sink: NotebookAgentSink) async {
        guard let (providerID, model) = LLMConfigStore.shared.activeSelection() else {
            sink.agentAddProse("> ⚠️ Configure an AI provider in Settings to use the research agent.")
            return
        }
        let meta = LLMConfigStore.shared.modelMeta(for: providerID, name: model)
        guard let provider = LLMService.shared.provider(for: providerID, model: meta) as? OpenAICompatibleProvider else {
            sink.agentAddProse("> ⚠️ The active AI provider can't run tools.")
            return
        }
        let (files, corpus) = workspaceCorpus()

        // Sequential tool calls append here; applied to the sink after the loop.
        final class Buffer { var items: [(code: Bool, text: String, out: ExecOutput?)] = [] }
        let buf = Buffer()
        let effects = AgentToolEffects()
        effects.notebookAddProse = { buf.items.append((false, $0, nil)) }
        effects.notebookRunCode = { code in
            let r = MindoScriptRunner.run(code, on: MindMap(), corpus: corpus, allFiles: files)
            buf.items.append((true, code, ExecOutput(text: r.output, error: r.error)))
            return r.error.map { "error: \($0)" } ?? (r.output.isEmpty ? "(no output)" : r.output)
        }
        let tools = MindoAgentTools(map: MindMap(), corpus: corpus, allFiles: files,
                                    workspaceRoot: workspaceRoots.first?.url, effects: effects)
        // Read-only KB research + notebook authoring (no map/doc mutation).
        let allow: Set<String> = ["list_docs", "read_document", "resolve_link", "backlinks",
                                  "find_topics", "get_subtree", "semantic_search",
                                  "notebook_add_note", "notebook_add_code"]
        let specs = MindoAgentTools.descriptors.filter { allow.contains($0.name) }
            .map { ToolSpec(name: $0.name, description: $0.description, parametersJSON: $0.parametersJSON) }

        let system = """
        You are a research assistant writing INTO a notebook, not chatting. Research the \
        user's question using the knowledge-base tools (semantic_search, read_document, \
        backlinks, find_topics). Build the answer by calling notebook_add_note (Markdown \
        prose findings — cite the source document names inline) and notebook_add_code (Lua \
        over the `mindo` API to compute or verify a point). Prefer several short notes and \
        code cells over one long note. Don't narrate to the user; put everything in the \
        notebook. Stop when the question is answered.
        """
        let messages: [ChatMessage] = [.system(system), .user(question)]
        let backend = AgentToolBackend(messages: messages, tools: specs) { msgs, offered in
            let input = LLMInput(providerID: providerID.rawValue, model: model, text: "",
                                 messages: msgs, tools: offered, isStreaming: false)
            return try await provider.complete(input)
        }
        _ = try? await AgentLoop.run(backend: backend, maxIterations: 10) { call in
            tools.handle(name: call.name, argumentsJSON: call.argumentsJSON)
        }

        if buf.items.isEmpty {
            sink.agentAddProse("> The agent didn't produce any notebook content for that question.")
        } else {
            for item in buf.items {
                if item.code, let out = item.out { sink.agentAddCode(item.text, output: out) }
                else { sink.agentAddProse(item.text) }
            }
        }
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
