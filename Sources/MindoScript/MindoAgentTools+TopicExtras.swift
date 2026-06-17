import Foundation
import MindoModel

// G4 — Topic extras: notes, jump-links, collapse. Implemented by the agent-tools sprint.
extension MindoAgentTools {
    static let topicExtrasDescriptors: [(name: String, description: String, parametersJSON: String)] = []

    func handleTopicExtras(_ name: String, _ a: ToolArgs) -> String? { nil }
}
