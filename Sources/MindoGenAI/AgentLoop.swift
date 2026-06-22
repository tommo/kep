import Foundation

/// Errors from the agent tool-calling loop.
public enum AgentError: Error, Equatable {
    case iterationLimit(Int)
}

/// Provider-agnostic tool-calling loop. The backend owns how it talks to the
/// model (message/tool serialization); the loop just drives the cycle:
/// ask for the next step → if the model requested tools, execute them and feed
/// the results back → repeat until a final text reply or the iteration cap.
///
/// Pure orchestration, so it's tested with a mock backend + handler — no network.
public enum AgentLoop {
    /// What the model decided this round.
    public enum Step: Equatable {
        case reply(String)        // final assistant text
        case call([ToolCall])     // tools to execute, then loop
    }

    /// The model side of the loop. A class so the loop can drive it statefully
    /// (it accumulates messages + tool results internally).
    public protocol Backend: AnyObject {
        /// The model's next step given the conversation so far.
        func next() async throws -> Step
        /// Record executed tool results to include in the next `next()` call.
        func record(_ results: [(call: ToolCall, result: String)])
    }

    /// Run the loop. `execute` runs one tool call and returns its result string
    /// (JSON/text) to feed back to the model.
    @discardableResult
    public static func run(backend: Backend,
                           maxIterations: Int = 100,
                           execute: (ToolCall) async -> String) async throws -> String {
        for _ in 0..<max(1, maxIterations) {
            switch try await backend.next() {
            case .reply(let text):
                return text
            case .call(let calls):
                var results: [(call: ToolCall, result: String)] = []
                for c in calls { results.append((c, await execute(c))) }
                backend.record(results)
            }
        }
        throw AgentError.iterationLimit(maxIterations)
    }
}
