import Foundation

// G2 — Document editing (disk writes). Implemented by the agent-tools sprint.
extension MindoAgentTools {
    static let docEditDescriptors: [(name: String, description: String, parametersJSON: String)] = []

    func handleDocEdit(_ name: String, _ a: ToolArgs) -> String? { nil }
}
