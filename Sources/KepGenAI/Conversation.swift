import Foundation

/// A multi-turn chat conversation — the model behind the agentic dialog view.
/// Pure value logic (no networking, no UI) so turn-building, context injection,
/// and history trimming are unit-testable; the view drives it and hands
/// `llmMessages()` to `LLMService`.
public struct Conversation: Sendable, Equatable {

    /// One visible turn. `system` turns are not shown but are sent to the model.
    public struct Turn: Identifiable, Sendable, Equatable {
        public let id: UUID
        public var role: ChatMessage.Role
        public var content: String
        public init(id: UUID = UUID(), role: ChatMessage.Role, content: String) {
            self.id = id
            self.role = role
            self.content = content
        }
    }

    /// Standing instruction sent as the first `system` message every request.
    public var systemPrompt: String
    /// Ephemeral context (active document, selection, resolved links) refreshed
    /// per send and appended after the system prompt as its own `system` turn.
    public var contextBlock: String?
    /// Visible user/assistant turns, oldest first.
    public private(set) var turns: [Turn]
    /// Cap on user+assistant turns kept for the request (0 = unlimited). Older
    /// turns are dropped from the wire payload but stay in `turns` for display.
    public var historyLimit: Int

    public init(systemPrompt: String = Conversation.defaultSystemPrompt,
                contextBlock: String? = nil,
                turns: [Turn] = [],
                historyLimit: Int = 20) {
        self.systemPrompt = systemPrompt
        self.contextBlock = contextBlock
        self.turns = turns
        self.historyLimit = historyLimit
    }

    public static let defaultSystemPrompt =
        "You are Kep's built-in assistant. Help the user with the document they are "
        + "editing — mind maps, Markdown notes, PlantUML diagrams, and CSV tables. Be concise. "
        + "When asked to produce a diagram or table, output only valid source for that format."

    // MARK: - Mutation

    @discardableResult
    public mutating func addUser(_ text: String) -> Turn {
        let t = Turn(role: .user, content: text)
        turns.append(t)
        return t
    }

    @discardableResult
    public mutating func addAssistant(_ text: String) -> Turn {
        let t = Turn(role: .assistant, content: text)
        turns.append(t)
        return t
    }

    /// Append streamed text to the last assistant turn, creating one if the last
    /// turn isn't already an assistant turn. Lets the view stream into history.
    public mutating func appendToLastAssistant(_ delta: String) {
        if let last = turns.last, last.role == .assistant {
            turns[turns.count - 1].content += delta
        } else {
            turns.append(Turn(role: .assistant, content: delta))
        }
    }

    public mutating func clear() { turns.removeAll() }

    // MARK: - Wire payload

    /// The messages to send: system prompt, optional context block, then the
    /// most recent `historyLimit` visible turns (empty turns dropped).
    public func llmMessages() -> [ChatMessage] {
        var out: [ChatMessage] = []
        if !systemPrompt.isEmpty { out.append(.system(systemPrompt)) }
        if let ctx = contextBlock, !ctx.isEmpty { out.append(.system(ctx)) }
        let visible = turns.filter { !$0.content.isEmpty }
        let kept = historyLimit > 0 ? Array(visible.suffix(historyLimit)) : visible
        out.append(contentsOf: kept.map { ChatMessage(role: $0.role, content: $0.content) })
        return out
    }
}
