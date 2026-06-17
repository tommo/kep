import XCTest
@testable import MindoGenAI

final class AgentToolBackendTests: XCTestCase {

    private let tools = [ToolSpec(name: "resolve_link", description: "resolve")]

    func testThreadsToolCallThenReply() async throws {
        let call = ToolCall(id: "c1", name: "resolve_link", argumentsJSON: #"{"target":"Roadmap"}"#)
        // First completion asks for a tool; second (after the result) replies.
        var round = 0
        let backend = AgentToolBackend(messages: [.user("open roadmap")], tools: tools) { msgs, offered in
            XCTAssertEqual(offered.first?.name, "resolve_link")
            round += 1
            if round == 1 { return ("", [call]) }
            // On the 2nd call the tool result must be in the history.
            XCTAssertTrue(msgs.contains { $0.role == .tool && $0.content == "Roadmap.md" })
            return ("Opened Roadmap.md", [])
        }

        let reply = try await AgentLoop.run(backend: backend) { c in
            c.name == "resolve_link" ? "Roadmap.md" : "?"
        }
        XCTAssertEqual(reply, "Opened Roadmap.md")

        // History: user, assistant(tool_calls), tool result, assistant(final).
        let roles = backend.history.map(\.role)
        XCTAssertEqual(roles, [.user, .assistant, .tool, .assistant])
        XCTAssertEqual(backend.history[1].toolCalls?.first?.id, "c1")
        XCTAssertEqual(backend.history[2].toolCallID, "c1")
        XCTAssertEqual(backend.history.last?.content, "Opened Roadmap.md")
    }

    func testImmediateReplyNoTools() async throws {
        let backend = AgentToolBackend(messages: [.user("hi")], tools: tools) { _, _ in ("hello", []) }
        let reply = try await AgentLoop.run(backend: backend) { _ in "" }
        XCTAssertEqual(reply, "hello")
        XCTAssertEqual(backend.history.map(\.role), [.user, .assistant])
    }
}
