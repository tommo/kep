import XCTest
@testable import MindoGenAI

/// Scripted backend: returns a queued sequence of steps; records tool results
/// so the test can assert they were fed back.
private final class MockBackend: AgentLoop.Backend {
    var steps: [AgentLoop.Step]
    var recorded: [[(call: ToolCall, result: String)]] = []
    init(_ steps: [AgentLoop.Step]) { self.steps = steps }
    func next() async throws -> AgentLoop.Step { steps.removeFirst() }
    func record(_ results: [(call: ToolCall, result: String)]) { recorded.append(results) }
}

final class AgentLoopTests: XCTestCase {

    func testImmediateReply() async throws {
        let backend = MockBackend([.reply("hello")])
        let out = try await AgentLoop.run(backend: backend) { _ in "" }
        XCTAssertEqual(out, "hello")
        XCTAssertTrue(backend.recorded.isEmpty)
    }

    func testExecutesToolsThenReplies() async throws {
        let call = ToolCall(id: "1", name: "resolve_link", argumentsJSON: #"{"target":"Roadmap"}"#)
        let backend = MockBackend([.call([call]), .reply("done")])
        var executed: [String] = []
        let out = try await AgentLoop.run(backend: backend) { c in
            executed.append(c.name)
            return "Roadmap.md"
        }
        XCTAssertEqual(out, "done")
        XCTAssertEqual(executed, ["resolve_link"])
        // The tool result was fed back to the backend.
        XCTAssertEqual(backend.recorded.count, 1)
        XCTAssertEqual(backend.recorded[0][0].result, "Roadmap.md")
    }

    func testMultipleToolsInOneStep() async throws {
        let calls = [ToolCall(id: "1", name: "a", argumentsJSON: "{}"),
                     ToolCall(id: "2", name: "b", argumentsJSON: "{}")]
        let backend = MockBackend([.call(calls), .reply("ok")])
        var count = 0
        _ = try await AgentLoop.run(backend: backend) { _ in count += 1; return "r" }
        XCTAssertEqual(count, 2)
        XCTAssertEqual(backend.recorded[0].count, 2)
    }

    func testIterationLimitThrows() async {
        // Backend always asks for more tools → never replies.
        let backend = MockBackend(Array(repeating: .call([ToolCall(id: "x", name: "loop", argumentsJSON: "{}")]), count: 20))
        do {
            _ = try await AgentLoop.run(backend: backend, maxIterations: 3) { _ in "r" }
            XCTFail("expected iterationLimit")
        } catch {
            XCTAssertEqual(error as? AgentError, .iterationLimit(3))
        }
    }
}
