import Foundation
import MindoCore
import MindoModel
import MindoMarkdown
import MindoScript
import MindoGenAI

/// One persistent Lua kernel per open notebook, so block ORDER and cross-block
/// DEPENDENCY behave like Jupyter: globals set in one cell are visible to later
/// cells, whether you Run-All or run cells one at a time — and the agent runs in
/// the SAME kernel, so it's a node in the chain (sees prior state, its code
/// feeds later cells). Run All restarts the kernel (clean top-to-bottom =
/// reproducible); per-cell Run and the agent use the live, accumulated state.
@MainActor
final class NotebookKernelStore {
    static let shared = NotebookKernelStore()
    private var kernels: [String: MindoNotebookKernel] = [:]
    private func key(_ url: URL?) -> String { url?.standardizedFileURL.path ?? "·untitled·" }

    /// The kernel for a notebook. `restart: true` builds a fresh one (Run All).
    func kernel(for url: URL?, restart: Bool, build: () -> MindoNotebookKernel?) -> MindoNotebookKernel? {
        let k = key(url)
        if !restart, let existing = kernels[k] { return existing }
        kernels[k] = build()
        return kernels[k]
    }
    /// Drop a notebook's kernel (closed doc / explicit restart).
    func reset(_ url: URL?) { kernels[key(url)] = nil }
}

/// Bridges the Research Notebook editor's injected run closures to the
/// MindoScript Lua kernel. Lives in the app target (which imports both
/// MindoMarkdown and MindoScript) so MindoMarkdown stays free of a scripting
/// dependency — same pattern as the CSV agent-tool injection.
extension AppSession {

    /// Build a notebook kernel over the current workspace KB (scratch map — Lua
    /// can read the KB and compute, but map mutations stay scratch-only so the
    /// user's open mind map is never touched).
    @MainActor
    private func buildNotebookKernel() -> MindoNotebookKernel? {
        let (files, corpus) = workspaceCorpus()
        guard let kernel = try? MindoNotebookKernel(map: MindMap(), corpus: corpus, allFiles: files) else { return nil }
        loadNotebookLibraries(into: kernel)
        return kernel
    }

    /// User-extensible Lua arsenal, loaded into the kernel in order so a user's
    /// own helpers are available in every notebook cell and to the agent:
    ///   1. global  `~/Library/Application Support/Mindo/notebook.lua`
    ///   2. per vault: `<root>/notebook.lua`, then `<root>/lib/*.lua` (alphabetical)
    /// Later files run last and can extend/override earlier ones (one shared VM).
    /// A broken library surfaces an error but doesn't break the kernel. Edits
    /// take effect on the next kernel rebuild (Run All).
    @MainActor
    private func loadNotebookLibraries(into kernel: MindoNotebookKernel) {
        var urls = [MindoCore.applicationSupportURL.appendingPathComponent("notebook.lua")]
        for root in workspaceRoots {
            urls.append(root.url.appendingPathComponent("notebook.lua"))
            let libDir = root.url.appendingPathComponent("lib")
            if let files = try? FileManager.default.contentsOfDirectory(at: libDir, includingPropertiesForKeys: nil) {
                urls += files.filter { $0.pathExtension.lowercased() == "lua" }
                             .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            }
        }
        var errors: [String] = []
        for url in urls {
            guard let src = try? String(contentsOf: url, encoding: .utf8),
                  !src.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let err = kernel.loadLibrary(src, name: url.lastPathComponent) { errors.append(err) }
        }
        if !errors.isEmpty { lastError = "Notebook library error — " + errors.joined(separator: "; ") }
    }

    /// Run All — RESTART the shared kernel and run every code cell top-to-bottom
    /// (the reproducible path). The post-run kernel state stays live, so later
    /// per-cell runs and the agent continue from it.
    @MainActor
    func runNotebookAll(_ notebook: Notebook, in ctx: NotebookRunContext) async -> ExecOutputs {
        var outputs = ctx.documentURL.map { ExecOutputsStore.load(for: $0) } ?? ExecOutputs()
        guard let kernel = NotebookKernelStore.shared.kernel(for: ctx.documentURL, restart: true,
                                                             build: buildNotebookKernel) else {
            return outputs
        }
        var live = Set<String>()
        for case .code(_, _, let code) in notebook.cells {
            let result = kernel.run(code)
            let hash = MarkdownExecBlocks.hash(code)
            outputs.set(ExecOutput(text: result.output, error: result.error, errorLine: result.errorLine), forHash: hash)
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
    func runNotebookAgent(_ question: String, context: String, in ctx: NotebookRunContext, into sink: NotebookAgentSink) async {
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

        // Stream authored cells to the notebook AS the agent works (the loop runs
        // off the main actor; each cell hops to the @MainActor sink). FIFO Task
        // enqueue preserves authoring order.
        final class Flag { var authored = false }
        let flag = Flag()
        let effects = AgentToolEffects()
        effects.notebookAddProse = { text in
            flag.authored = true
            Task { @MainActor in sink.agentAddProse(text) }
        }
        let docURL = ctx.documentURL
        let tools = MindoAgentTools(map: MindMap(), corpus: corpus, allFiles: files,
                                    workspaceRoot: workspaceRoots.first?.url, effects: effects)

        // CodeAct: the agent's SINGLE action is Lua (`notebook_eval`) run in the
        // notebook's shared kernel — research, compute, and authoring all happen
        // in code (including embedding retrieval via kep.semanticSearch). Wire
        // the kernel's authoring hooks so `nb.note`/`nb.code` emit cells into THIS
        // notebook; clear them when the run ends.
        let kernel = NotebookKernelStore.shared.kernel(for: docURL, restart: false, build: buildNotebookKernel)
        kernel?.onNote = { md in flag.authored = true; sink.agentAddProse(md) }
        kernel?.onCode = { src in flag.authored = true; sink.agentAddCode(src, output: nil) }
        defer { kernel?.onNote = nil; kernel?.onCode = nil }

        let allow: Set<String> = ["notebook_eval"]
        let specs = MindoAgentTools.descriptors.filter { allow.contains($0.name) }
            .map { ToolSpec(name: $0.name, description: $0.description, parametersJSON: $0.parametersJSON) }

        let system = """
        You are a research assistant working IN a notebook through CODE (CodeAct). Your main \
        action is `notebook_eval`: write Lua, it runs in the notebook's LIVE shared session and \
        returns its printed output, which you observe and build on. Iterate — inspect, refine — \
        and fix your own Lua from any error message. State persists across actions, so assign \
        NAMED globals to reuse.

        In Lua you can:
        • Research the workspace knowledge base — kep.semanticSearch(query [, k]) for \
        meaning-based retrieval; kep.search(query) for literal keyword snippets; kep.docs() \
        lists document names; kep.readDoc(name) returns a document's text; kep.backlinks(name) \
        lists what links to it.
        • Author the notebook (this is HOW you produce the answer) — nb.note(markdown) adds a \
        prose cell (cite the source document names inline); nb.code(luaSource) adds a Lua code \
        cell the reader can run.
        • Compute and print(...) to observe.

        Continue the notebook you're given (don't repeat what's above). Build the answer as \
        several short nb.note / nb.code cells grounded in what you actually read and computed. \
        Don't narrate to the user outside the notebook; reply with a one-line summary when done.
        """
        let notebookSoFar = context.trimmingCharacters(in: .whitespacesAndNewlines)
        var messages: [ChatMessage] = [.system(system)]
        if !notebookSoFar.isEmpty {
            messages.append(.system("The notebook so far (cells above your block):\n\n\(notebookSoFar)"))
        }
        messages.append(.user(question))
        let backend = AgentToolBackend(messages: messages, tools: specs) { msgs, offered in
            let input = LLMInput(providerID: providerID.rawValue, model: model, text: "",
                                 messages: msgs, tools: offered, isStreaming: false)
            return try await provider.complete(input)
        }
        // Track which documents the agent actually read → block provenance.
        final class Sources { var names: [String] = [] }
        let sources = Sources()
        _ = try? await AgentLoop.run(backend: backend, maxIterations: 10) { call in
            if call.name == "read_document" || call.name == "resolve_link",
               let name = Self.argString(call.argumentsJSON, call.name == "read_document" ? "name" : "target"),
               !sources.names.contains(name) {
                sources.names.append(name)
            }
            let step = Self.describeCall(call)
            Task { @MainActor in sink.agentLog(step) }   // live "watch it work" trace

            // Code runs in the notebook's PERSISTENT kernel so the agent is a node
            // in the dependency chain: it sees globals from cells already run, and
            // its own definitions persist for the cells it (and the user) add after.
            // `await MainActor.run` hops to the kernel without blocking the loop.
            if call.name == "notebook_add_code", let code = Self.argString(call.argumentsJSON, "code") {
                flag.authored = true
                let out: ExecOutput = await MainActor.run {
                    let r = NotebookKernelStore.shared.kernel(for: docURL, restart: false,
                                                              build: self.buildNotebookKernel)?.run(code)
                        ?? ScriptRunResult(output: "", error: "executor unavailable")
                    let o = ExecOutput(text: r.output, error: r.error, errorLine: r.errorLine)
                    sink.agentAddCode(code, output: o)
                    return o
                }
                if let err = out.error { return "error: \(err)" }
                return out.text.isEmpty ? "ran the cell (no output)" : "cell output:\n\(out.text)"
            }
            // Read a value FROM the live kernel without authoring a cell — lets
            // the agent inspect data that code cells computed.
            if call.name == "notebook_eval", let code = Self.argString(call.argumentsJSON, "code") {
                return await MainActor.run {
                    let r = NotebookKernelStore.shared.kernel(for: docURL, restart: false,
                                                              build: self.buildNotebookKernel)?.run(code)
                        ?? ScriptRunResult(output: "", error: "executor unavailable")
                    if let err = r.error { return "error: \(err)" }
                    return r.output.isEmpty ? "(no value)" : r.output
                }
            }
            return tools.handle(name: call.name, argumentsJSON: call.argumentsJSON)
        }
        // Let the last streamed Task land before reporting / setting provenance.
        await Task.yield()
        if !sources.names.isEmpty { sink.agentSetSources(sources.names) }
        if !flag.authored {
            sink.agentAddProse("> The agent didn't produce any notebook content for that question.")
        }
    }

    /// Pull a string arg out of a tool call's JSON arguments.
    private static func argString(_ json: String, _ key: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj[key] as? String
    }

    /// A short, human-readable line for the agent block's research-steps trace.
    private static func describeCall(_ call: ToolCall) -> String {
        let a = call.argumentsJSON
        switch call.name {
        case "semantic_search":  return "🔎 searched: \(argString(a, "query") ?? "")"
        case "find_topics":      return "🔎 found topics: \(argString(a, "query") ?? "")"
        case "read_document":    return "📄 read: \(argString(a, "name") ?? "")"
        case "resolve_link":     return "🔗 resolved: \(argString(a, "target") ?? "")"
        case "backlinks":        return "🔗 backlinks: \(argString(a, "name") ?? "")"
        case "get_subtree":      return "🌳 read subtree"
        case "list_docs":        return "📑 listed documents"
        case "notebook_add_note": return "✎ wrote a note"
        case "notebook_add_code": return "λ ran a query"
        case "notebook_eval":     return "λ ran code"
        default:                 return "• \(call.name)"
        }
    }

    /// Run a single cell against the notebook's PERSISTENT kernel (Jupyter-style:
    /// it sees globals from cells already run). Load-modify-save the sidecar so a
    /// one-cell run doesn't drop sibling outputs.
    @MainActor
    func runNotebookCell(_ source: String, in ctx: NotebookRunContext) async -> ExecOutput {
        let result = NotebookKernelStore.shared.kernel(for: ctx.documentURL, restart: false,
                                                       build: buildNotebookKernel)?.run(source)
            ?? ScriptRunResult(output: "", error: "executor unavailable")
        let out = ExecOutput(text: result.output, error: result.error, errorLine: result.errorLine)
        if let url = ctx.documentURL {
            var store = ExecOutputsStore.load(for: url)
            store.set(out, forHash: MarkdownExecBlocks.hash(source))
            try? ExecOutputsStore.save(store, for: url)
        }
        return out
    }
}
