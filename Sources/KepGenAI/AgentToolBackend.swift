import Foundation

/// `AgentLoop.Backend` over a chat-completion model: holds the `ChatMessage`
/// history, asks the model (via an injected `complete`) for the next step with
/// tools offered, and threads assistant tool-call + tool-result messages back
/// in. The `complete` closure is injectable so this is tested without network.
public final class AgentToolBackend: AgentLoop.Backend {
    /// Run one completion: given the conversation + tools, return assistant text
    /// and any tool calls. (The live impl wraps `OpenAICompatibleProvider.complete`.)
    public typealias Complete = ([ChatMessage], [ToolSpec]) async throws -> (text: String, toolCalls: [ToolCall])

    private(set) public var history: [ChatMessage]
    private let tools: [ToolSpec]
    private let complete: Complete

    public init(messages: [ChatMessage], tools: [ToolSpec], complete: @escaping Complete) {
        self.history = messages
        self.tools = tools
        self.complete = complete
    }

    public func next() async throws -> AgentLoop.Step {
        let (text, calls) = try await complete(history, tools)
        if calls.isEmpty {
            history.append(.assistant(text))
            return .reply(text)
        }
        history.append(.assistant(text, toolCalls: calls))
        return .call(calls)
    }

    public func record(_ results: [(call: ToolCall, result: String)]) {
        for r in results {
            history.append(.toolResult(id: r.call.id, name: r.call.name, r.result))
        }
    }
}
