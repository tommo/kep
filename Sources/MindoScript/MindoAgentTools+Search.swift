import Foundation
import MindoCore

// G1 — Search & navigate (read-only). Implemented by the agent-tools sprint.
extension MindoAgentTools {
    static let searchDescriptors: [(name: String, description: String, parametersJSON: String)] = []

    func handleSearch(_ name: String, _ a: ToolArgs) -> String? { nil }
}
