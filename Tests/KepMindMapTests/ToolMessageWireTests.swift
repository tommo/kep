import XCTest
import Foundation
@testable import KepGenAI

final class ToolMessageWireTests: XCTestCase {

    private func provider() -> DeepSeekProvider {
        DeepSeekProvider(meta: ProviderMeta(apiKey: "k", endpoint: GenAIProviderID.deepSeek.defaultEndpoint),
                         model: ModelMeta(name: "deepseek-v4-flash"))
    }

    private func messages(_ ms: [ChatMessage]) throws -> [[String: Any]] {
        let input = LLMInput(providerID: GenAIProviderID.deepSeek.rawValue, model: "deepseek-v4-flash",
                             text: "x", messages: ms)
        let body = try JSONSerialization.jsonObject(with: provider().makeRequest(input, streaming: false).httpBody!) as! [String: Any]
        return body["messages"] as! [[String: Any]]
    }

    func testAssistantToolCallSerialized() throws {
        let call = ToolCall(id: "call_1", name: "resolve_link", argumentsJSON: #"{"target":"Roadmap"}"#)
        let wire = try messages([.user("find roadmap"), .assistant("", toolCalls: [call])])
        let assistant = wire[1]
        XCTAssertEqual(assistant["role"] as? String, "assistant")
        let calls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0]["id"] as? String, "call_1")
        let fn = calls[0]["function"] as! [String: Any]
        XCTAssertEqual(fn["name"] as? String, "resolve_link")
        XCTAssertEqual(fn["arguments"] as? String, #"{"target":"Roadmap"}"#)
    }

    func testToolResultSerialized() throws {
        let wire = try messages([.toolResult(id: "call_1", name: "resolve_link", "Roadmap.md")])
        let tool = wire[0]
        XCTAssertEqual(tool["role"] as? String, "tool")
        XCTAssertEqual(tool["tool_call_id"] as? String, "call_1")
        XCTAssertEqual(tool["name"] as? String, "resolve_link")
        XCTAssertEqual(tool["content"] as? String, "Roadmap.md")
    }

    func testPlainMessagesHaveNoToolFields() throws {
        let wire = try messages([.system("s"), .user("u")])
        XCTAssertNil(wire[0]["tool_calls"])
        XCTAssertNil(wire[1]["tool_call_id"])
    }
}
