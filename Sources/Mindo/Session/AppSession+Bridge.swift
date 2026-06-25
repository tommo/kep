import Foundation
import KepBridge
import MindoCore
import MindoModel
import MindoScript
import MindoCSV

/// Weak holder so a closed CSV tab's coordinator deallocs and the registry
/// entry resolves to nil (falling back to the disk path).
final class WeakCSVBridge {
    weak var bridge: CSVLiveBridge?
    init(_ bridge: CSVLiveBridge) { self.bridge = bridge }
}

// External-agent bridge: a Unix-socket server (KepBridge) that exposes kep's own
// agent tools to the `kep` CLI and `kep-mcp` MCP server, driving the LIVE app so
// edits reflect in open editors. Opt-in via PrefKeys.bridgeEnabled.
extension AppSession {

    /// The tools offered to external agents — kep's agent descriptors, minus the
    /// map-editing ones when no mind map is active (parity with the chat agent).
    @MainActor
    func bridgeDescriptors() -> [BridgeToolDescriptor] {
        let hasMap = activeMindMap != nil
        return MindoAgentTools.descriptors
            .filter { hasMap || !MindoAgentTools.mapMutatingToolNames.contains($0.name) }
            .map { BridgeToolDescriptor(name: $0.name, description: $0.description, parametersJSON: $0.parametersJSON) }
    }

    /// Register an open CSV editor's live-sheet bridge (keyed by URL).
    func registerLiveCSV(_ url: URL, _ bridge: CSVLiveBridge) {
        liveCSVBridges[url.standardizedFileURL] = WeakCSVBridge(bridge)
    }

    /// The live sheet for an OPEN CSV at `url`, or nil if it isn't open.
    func liveCSV(_ url: URL) -> CSVLiveBridge? {
        liveCSVBridges[url.standardizedFileURL]?.bridge
    }

    /// Wire the CSV tool effects to prefer the OPEN editor's live sheet (unsaved
    /// state + instant UI), falling back to the on-disk path when not open.
    /// Shared by the chat agent and the external bridge.
    func wireCSVEffects(_ effects: AgentToolEffects) {
        effects.csvCellValue = { [weak self] url, a1 in
            self?.liveCSV(url)?.liveReadCell(a1) ?? Self.csvReadCell(url, a1)
        }
        effects.csvSetCell = { [weak self] url, a1, v in
            if let live = self?.liveCSV(url) { return live.liveSetCell(a1, value: v) }
            return Self.csvWriteCell(url, a1, v)
        }
        effects.csvAddBlock = { [weak self] url, n, s in
            if let live = self?.liveCSV(url) { return live.liveAddBlock(name: n, source: s) }
            return Self.csvAddBlock(url, n, s)
        }
    }

    /// Run one external tool call against the live session, then reflect any
    /// changes in the UI (same path as the chat agent).
    @MainActor
    func bridgeCall(_ name: String, _ argumentsJSON: String) -> String {
        let (files, corpus) = workspaceCorpus()
        let hadMindMap = activeMindMap != nil
        let map = activeMindMap ?? MindMap(root: Topic(text: "Scratch"))
        let mapBefore = hadMindMap ? map.write() : ""
        let effects = AgentToolEffects()
        wireCSVEffects(effects)
        let tools = MindoAgentTools(map: map, corpus: corpus, allFiles: files,
                                    workspaceRoot: workspaceRoots.first?.url, effects: effects)
        let result = tools.handle(name: name, argumentsJSON: argumentsJSON)
        reflectAgentChanges(effects: effects, map: map, hadMindMap: hadMindMap, mapBefore: mapBefore)
        return result
    }

    /// Start the bridge socket server if enabled in prefs. The dispatcher runs on
    /// the socket's background thread but hops every call to the main actor.
    @MainActor
    func startBridge() {
        guard bridgeServer == nil, PrefKeys.bool(PrefKeys.bridgeEnabled, fallback: false) else { return }
        let dispatcher = BridgeDispatcher(
            listTools: { [weak self] in
                var out: [BridgeToolDescriptor] = []
                DispatchQueue.main.sync { MainActor.assumeIsolated { out = self?.bridgeDescriptors() ?? [] } }
                return out
            },
            call: { [weak self] name, args in
                var out = "error: kep session unavailable"
                DispatchQueue.main.sync { MainActor.assumeIsolated { out = self?.bridgeCall(name, args) ?? out } }
                return out
            })
        let server = KepBridgeServer { dispatcher.handleLine($0) }
        if server.start() { bridgeServer = server }
    }

    @MainActor
    func stopBridge() {
        bridgeServer?.stop()
        bridgeServer = nil
    }
}
