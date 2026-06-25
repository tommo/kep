import Foundation
import KepModel
import KepCore
import KepGenAI
import KepScript
import KepCSV

extension AppSession {

    /// The active document's mind map, if it is one.
    var activeMindMap: MindMap? {
        if case .mindMap(let map)? = activeDocument?.kind { return map }
        return nil
    }

    /// Run the agent tool-loop for a conversation and return the final reply.
    /// The model may call `kep` tools (resolve_link/list_docs/backlinks/
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

        let (files, corpus) = workspaceCorpus()
        let hadMindMap = activeMindMap != nil
        let map = activeMindMap ?? MindMap(root: Topic(text: "Scratch"))
        let mapBefore = hadMindMap ? map.write() : ""
        let effects = AgentToolEffects()
        // CSV tools prefer the OPEN editor's live sheet, else disk (see +Bridge).
        wireCSVEffects(effects)
        let tools = KepAgentTools(map: map, corpus: corpus, allFiles: files,
                                    workspaceRoot: workspaceRoots.first?.url, effects: effects)
        // Without an open mind map, omit the map-editing tools — their changes
        // would land on a throwaway scratch map and be discarded.
        let specs = KepAgentTools.descriptors
            .filter { hadMindMap || !KepAgentTools.mapMutatingToolNames.contains($0.name) }
            .map { ToolSpec(name: $0.name, description: $0.description, parametersJSON: $0.parametersJSON) }

        let backend = AgentToolBackend(messages: messages, tools: specs) { msgs, offered in
            let input = LLMInput(providerID: providerID.rawValue, model: model, text: "",
                                 messages: msgs, tools: offered, isStreaming: false)
            return try await provider.complete(input)
        }
        var usedTools: [String] = []
        let reply = try await AgentLoop.run(backend: backend, maxIterations: 100) { call in
            usedTools.append(call.name)
            return tools.handle(name: call.name, argumentsJSON: call.argumentsJSON)
        }

        reflectAgentChanges(effects: effects, map: map, hadMindMap: hadMindMap, mapBefore: mapBefore)
        // Show which tools ran, so the user sees what the agent did.
        guard !usedTools.isEmpty else { return reply }
        let trail = "🔧 " + usedTools.joined(separator: ", ")
        return reply.isEmpty ? trail : "\(trail)\n\n\(reply)"
    }

    /// Apply the side effects a tool run produced to the live session: reflect
    /// map edits (undoable + canvas reload), reload other tabs whose files were
    /// written, refresh the corpus + sidebar, and honor a select-topic request.
    /// Shared by the chat agent and the external bridge so both update the UI.
    @MainActor
    func reflectAgentChanges(effects: AgentToolEffects, map: MindMap, hadMindMap: Bool, mapBefore: String) {
        if effects.mapMutated, hadMindMap, let id = activeDocumentID,
           let idx = openDocuments.firstIndex(where: { $0.id == id }) {
            registerMapSnapshotUndo(map, before: mapBefore, after: map.write(), name: "AI Edit")
            openDocuments[idx].isDirty = true
            mindmapCommand = .reload
            mindmapCommandTick &+= 1
        }
        for url in effects.changedFiles {
            if let doc = openDocuments.first(where: {
                $0.fileURL?.standardizedFileURL == url.standardizedFileURL
            }) {
                let isActiveMutatedMap = doc.id == activeDocumentID && effects.mapMutated
                if !isActiveMutatedMap { reloadTab(doc.id) }
            }
        }
        if !effects.changedFiles.isEmpty { workspaceContentVersion &+= 1 }
        if !effects.createdFiles.isEmpty { reloadAllWorkspaces() }
        if let path = effects.selectTopicPath { requestOutlineNavigation(target: path) }
    }
}

extension AppSession {
    /// Load a CSV file + its sidecar as a CSVSheet (no header row — the grid
    /// treats every row as data), recomputing formulas.
    private static func loadSheet(_ url: URL) -> CSVSheet {
        let csv = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let sidecar = try? String(contentsOf: CSVSheetExtras.sidecarURL(for: url), encoding: .utf8)
        let sheet = CSVSheet.load(csv: csv, sidecar: sidecar, hasHeader: false)
        sheet.recompute()
        return sheet
    }

    /// Read a cell's formula source (if any) or baked value at an A1 ref.
    static func csvReadCell(_ url: URL, _ a1: String) -> String? {
        guard let ref = CSVCellRef(a1: a1) else { return nil }
        let sheet = loadSheet(url)
        return sheet.formula(at: ref) ?? sheet.value(at: ref)
    }

    /// Set a cell (literal or "=formula") at an A1 ref, growing the sheet to fit,
    /// then write the baked `.csv` + the sidecar back to disk. Returns success.
    /// Author a named Lua sheet block into a CSV on disk (parity with
    /// csvWriteCell): append the block, recompute (bakes any cell that references
    /// it via =name), persist CSV + sidecar. Returns the block's computed result
    /// or an error for the agent's tool response.
    static func csvAddBlock(_ url: URL, _ name: String, _ source: String) -> String {
        let sheet = loadSheet(url)
        sheet.extras.blocks.append(CSVEvalBlock(name: name, source: source))
        let result = CSVBlockRunner.run(sheet.extras.blocks, over: sheet.document).last
        sheet.recompute()   // no-op if no formula cells; bakes any =name references
        do {
            try sheet.bakedCSV().write(to: url, atomically: true, encoding: .utf8)
            let sidecar = CSVSheetExtras.sidecarURL(for: url)
            if let json = sheet.sidecarJSON() {
                try json.write(to: sidecar, atomically: true, encoding: .utf8)
            }
        } catch {
            return "error: couldn't save"
        }
        if let e = result?.error { return "errored: \(e)" }
        return "= \(result?.value ?? "")"
    }

    static func csvWriteCell(_ url: URL, _ a1: String, _ value: String) -> Bool {
        guard let ref = CSVCellRef(a1: a1) else { return false }
        let sheet = loadSheet(url)
        while sheet.document.rows.count <= ref.row { sheet.document.appendRow() }
        sheet.setCell(ref, to: value)   // routes "=…" to the extended layer + recompute
        do {
            try sheet.bakedCSV().write(to: url, atomically: true, encoding: .utf8)
            let sidecar = CSVSheetExtras.sidecarURL(for: url)
            if let json = sheet.sidecarJSON() {
                try json.write(to: sidecar, atomically: true, encoding: .utf8)
            } else if FileManager.default.fileExists(atPath: sidecar.path) {
                try? FileManager.default.removeItem(at: sidecar)
            }
            return true
        } catch {
            return false
        }
    }
}

enum AgentRunError: Error, LocalizedError {
    case noProvider
    var errorDescription: String? {
        switch self { case .noProvider: return "Configure an AI provider in Settings first." }
    }
}
