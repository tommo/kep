import Foundation
import MindoModel
import MindoCore
import MindoGenAI
import MindoScript

extension AppSession {

    /// The active document's mind map, if it is one.
    var activeMindMap: MindMap? {
        if case .mindMap(let map)? = activeDocument?.kind { return map }
        return nil
    }

    /// Run the agent tool-loop for a conversation and return the final reply.
    /// The model may call `mindo` tools (resolve_link/list_docs/backlinks/
    /// add_child_topic/run_lua) which act on the active mind map + workspace KB;
    /// the canvas reloads afterwards if the map was touched.
    @MainActor
    func agentReply(_ messages: [ChatMessage]) async throws -> String {
        guard let (providerID, model) = LLMConfigStore.shared.activeSelection() else {
            throw AgentRunError.noProvider
        }
        let meta = LLMConfigStore.shared.modelMeta(for: providerID, name: model)
        guard let provider = LLMService.shared.provider(for: providerID, model: meta) as? OpenAICompatibleProvider else {
            throw AgentRunError.noProvider
        }

        let files = quickSwitcherFiles().map(\.url)
        let corpus: [(url: URL, text: String)] = files.compactMap { u in
            (try? String(contentsOf: u, encoding: .utf8)).map { (u, $0) }
        }
        let hadMindMap = activeMindMap != nil
        let map = activeMindMap ?? MindMap(root: Topic(text: "Scratch"))
        let effects = AgentToolEffects()
        let tools = MindoAgentTools(map: map, corpus: corpus, allFiles: files,
                                    workspaceRoot: workspaceRoots.first?.url, effects: effects)
        // Without an open mind map, omit the map-editing tools — their changes
        // would land on a throwaway scratch map and be discarded.
        let specs = MindoAgentTools.descriptors
            .filter { hadMindMap || !MindoAgentTools.mapMutatingToolNames.contains($0.name) }
            .map { ToolSpec(name: $0.name, description: $0.description, parametersJSON: $0.parametersJSON) }

        let backend = AgentToolBackend(messages: messages, tools: specs) { msgs, offered in
            let input = LLMInput(providerID: providerID.rawValue, model: model, text: "",
                                 messages: msgs, tools: offered, isStreaming: false)
            return try await provider.complete(input)
        }
        var usedTools: [String] = []
        let reply = try await AgentLoop.run(backend: backend, maxIterations: 6) { call in
            usedTools.append(call.name)
            return tools.handle(name: call.name, argumentsJSON: call.argumentsJSON)
        }

        // Reflect any map mutations the tools made on the active canvas.
        if effects.mapMutated, hadMindMap, let id = activeDocumentID,
           let idx = openDocuments.firstIndex(where: { $0.id == id }) {
            openDocuments[idx].isDirty = true
            mindmapCommand = .reload
            mindmapCommandTick &+= 1
        }
        // Reload any *other* open tab whose file the agent wrote to disk. Skip
        // the active doc — if it's the mutated mind map, the in-memory reload
        // above already reflects it, and reloading from disk would clobber it.
        for url in effects.changedFiles {
            if let doc = openDocuments.first(where: {
                $0.fileURL?.standardizedFileURL == url.standardizedFileURL
            }), doc.id != activeDocumentID {
                reloadTab(doc.id)
            }
        }
        // Surface newly-created files in the sidebar.
        if !effects.createdFiles.isEmpty {
            reloadAllWorkspaces()
        }
        // Show which tools ran, so the user sees what the agent did.
        guard !usedTools.isEmpty else { return reply }
        let trail = "🔧 " + usedTools.joined(separator: ", ")
        return reply.isEmpty ? trail : "\(trail)\n\n\(reply)"
    }
}

enum AgentRunError: Error, LocalizedError {
    case noProvider
    var errorDescription: String? {
        switch self { case .noProvider: return "Configure an AI provider in Settings first." }
    }
}
