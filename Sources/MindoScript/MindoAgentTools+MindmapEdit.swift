import Foundation
import MindoModel

// G3 — Mindmap structural edits. Implemented by the agent-tools sprint.
extension MindoAgentTools {
    static let mindmapEditDescriptors: [(name: String, description: String, parametersJSON: String)] = []

    func handleMindmapEdit(_ name: String, _ a: ToolArgs) -> String? { nil }
}
