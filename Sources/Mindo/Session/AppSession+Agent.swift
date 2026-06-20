import Foundation
import MindoModel
import MindoCore
import MindoGenAI
import MindoScript
import MindoCSV

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

        let (files, corpus) = workspaceCorpus()
        let hadMindMap = activeMindMap != nil
        let map = activeMindMap ?? MindMap(root: Topic(text: "Scratch"))
        let mapBefore = hadMindMap ? map.write() : ""
        let effects = AgentToolEffects()
        // Inject CSV cell read/write (the spreadsheet model lives in MindoCSV).
        effects.csvCellValue = { url, a1 in Self.csvReadCell(url, a1) }
        effects.csvSetCell = { url, a1, value in Self.csvWriteCell(url, a1, value) }
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

        // Reflect any map mutations the tools made on the active canvas, as one
        // undoable step.
        if effects.mapMutated, hadMindMap, let id = activeDocumentID,
           let idx = openDocuments.firstIndex(where: { $0.id == id }) {
            registerMapSnapshotUndo(map, before: mapBefore, after: map.write(), name: "AI Edit")
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
            }) {
                // Skip only the active mind map (reloaded in-memory above);
                // an active CSV the agent edited still needs a disk reload.
                let isActiveMutatedMap = doc.id == activeDocumentID && effects.mapMutated
                if !isActiveMutatedMap { reloadTab(doc.id) }
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
