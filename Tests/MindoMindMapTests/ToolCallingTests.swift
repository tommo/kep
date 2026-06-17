import XCTest
import Foundation
@testable import MindoGenAI

final class ToolCallingTests: XCTestCase {

    private func provider() -> DeepSeekProvider {
        DeepSeekProvider(meta: ProviderMeta(apiKey: "k", endpoint: GenAIProviderID.deepSeek.defaultEndpoint),
                         model: ModelMeta(name: "deepseek-v4-flash"))
    }

    func testRequestOmitsToolsWhenNone() throws {
        let input = LLMInput(providerID: GenAIProviderID.deepSeek.rawValue, model: "deepseek-v4-flash", text: "hi")
        let req = try provider().makeRequest(input, streaming: false)
        let obj = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        XCTAssertNil(obj["tools"])
    }

    func testRequestSerializesTools() throws {
        let tools = [
            ToolSpec(name: "resolve_link", description: "Resolve a wiki link",
                     parametersJSON: #"{"type":"object","properties":{"target":{"type":"string"}},"required":["target"]}"#),
            ToolSpec(name: "list_docs", description: "List workspace docs"),
        ]
        let input = LLMInput(providerID: GenAIProviderID.deepSeek.rawValue, model: "deepseek-v4-flash",
                             text: "use a tool", tools: tools)
        let req = try provider().makeRequest(input, streaming: false)
        let obj = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
        let wire = try XCTUnwrap(obj["tools"] as? [[String: Any]])
        XCTAssertEqual(wire.count, 2)
        XCTAssertEqual(obj["tool_choice"] as? String, "auto")
        let fn0 = wire[0]["function"] as! [String: Any]
        XCTAssertEqual(fn0["name"] as? String, "resolve_link")
        // The JSON-schema string is embedded as a nested object, not a string.
        let params = try XCTUnwrap(fn0["parameters"] as? [String: Any])
        XCTAssertEqual(params["type"] as? String, "object")
        let required = params["required"] as? [String]
        XCTAssertEqual(required, ["target"])
    }

    func testParseToolCalls() {
        let json = #"""
        {"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[
          {"id":"call_1","type":"function","function":{"name":"resolve_link","arguments":"{\"target\":\"Roadmap\"}"}},
          {"id":"call_2","type":"function","function":{"name":"list_docs","arguments":"{}"}}
        ]}}]}
        """#
        let calls = OpenAICompatibleProvider.parseToolCalls(Data(json.utf8))
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].id, "call_1")
        XCTAssertEqual(calls[0].name, "resolve_link")
        XCTAssertEqual(calls[0].argumentsJSON, #"{"target":"Roadmap"}"#)
        XCTAssertEqual(calls[1].name, "list_docs")
    }

    func testParseToolCallsEmptyForPlainReply() {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"hello"}}]}"#
        XCTAssertTrue(OpenAICompatibleProvider.parseToolCalls(Data(json.utf8)).isEmpty)
    }
}
