import XCTest
import MindoGenAI

final class SSEParserTests: XCTestCase {
    func testParsesSingleEvent() {
        var p = SSEParser()
        let events = p.append("data: hello\n\n")
        XCTAssertEqual(events, [SSEParser.Event(data: "hello")])
    }

    func testHandlesChunkedDelivery() {
        var p = SSEParser()
        XCTAssertEqual(p.append("data: he"), [])
        XCTAssertEqual(p.append("llo\n"), [])
        XCTAssertEqual(p.append("\n"), [SSEParser.Event(data: "hello")])
    }

    func testIgnoresCommentLines() {
        var p = SSEParser()
        let events = p.append(": keepalive\n\ndata: real\n\n")
        XCTAssertEqual(events, [SSEParser.Event(data: "real")])
    }

    func testJoinsMultipleDataLinesWithNewline() {
        var p = SSEParser()
        let events = p.append("data: line1\ndata: line2\n\n")
        XCTAssertEqual(events, [SSEParser.Event(data: "line1\nline2")])
    }

    func testRecognizesDoneSentinel() {
        var p = SSEParser()
        let events = p.append("data: [DONE]\n\n")
        XCTAssertEqual(events, [SSEParser.Event(data: "[DONE]")])
    }
}

final class OpenAIProviderResponseTests: XCTestCase {
    func testParsePredictResponseExtractsContent() throws {
        let json = """
        {
          "choices": [{
            "message": {"role": "assistant", "content": "Hello there"}
          }],
          "usage": {"completion_tokens": 7}
        }
        """.data(using: .utf8)!
        let partial = try OpenAICompatibleProvider.parsePredictResponse(json)
        XCTAssertEqual(partial.text, "Hello there")
        XCTAssertEqual(partial.outputTokens, 7)
        XCTAssertTrue(partial.isStop)
    }

    func testParsePredictResponseSurfacesAPIError() {
        let json = """
        {"error": {"message": "invalid api key"}}
        """.data(using: .utf8)!
        XCTAssertThrowsError(try OpenAICompatibleProvider.parsePredictResponse(json)) { error in
            guard case LLMError.decoding(let msg) = error else {
                XCTFail("expected .decoding, got \(error)")
                return
            }
            XCTAssertEqual(msg, "invalid api key")
        }
    }

    func testParseStreamEventExtractsDelta() {
        let json = #"{"choices":[{"delta":{"content":"world"}}]}"#
        let partial = OpenAICompatibleProvider.parseStreamEvent(json)
        XCTAssertEqual(partial?.text, "world")
        XCTAssertFalse(partial?.isStop ?? true)
    }

    func testParseStreamEventDetectsFinishReason() {
        let json = #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#
        let partial = OpenAICompatibleProvider.parseStreamEvent(json)
        XCTAssertNotNil(partial)
        XCTAssertTrue(partial?.isStop ?? false)
    }
}

final class LLMConfigStoreTests: XCTestCase {
    func testRoundTripsThroughJSONFile() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mindo-llm-\(UUID())")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store = LLMConfigStore(directory: tmp)
        store.setProviderMeta(ProviderMeta(apiKey: "sk-secret", endpoint: ""), for: .openAI)
        store.addCustomModel(ModelMeta(name: "gpt-test", maxTokens: 1024), for: .openAI)

        let store2 = LLMConfigStore(directory: tmp)
        XCTAssertEqual(store2.providerMeta(for: .openAI).apiKey, "sk-secret")
        XCTAssertEqual(store2.providerMeta(for: .openAI).endpoint, GenAIProviderID.openAI.defaultEndpoint)
        XCTAssertTrue(store2.allModels(for: .openAI).contains { $0.name == "gpt-test" })
    }

    func testBuiltInModelsCoverMajorProviders() {
        XCTAssertFalse(BuiltInModels.models(for: .openAI).isEmpty)
        XCTAssertFalse(BuiltInModels.models(for: .deepSeek).isEmpty)
        XCTAssertFalse(BuiltInModels.models(for: .moonshot).isEmpty)
        XCTAssertFalse(BuiltInModels.models(for: .qwen).isEmpty)
        XCTAssertFalse(BuiltInModels.models(for: .ollama).isEmpty)
    }
}

final class LLMProviderFactoryTests: XCTestCase {
    func testFactoryCreatesOpenAICompatProviders() {
        for id in [GenAIProviderID.openAI, .ollama, .deepSeek, .moonshot, .qwen] {
            let p = LLMProviderFactory.create(
                providerID: id, meta: ProviderMeta(), model: ModelMeta(name: "x")
            )
            XCTAssertNotNil(p, "factory should create provider for \(id)")
            XCTAssertEqual(p?.providerID, id)
        }
    }

    func testFactoryReturnsAProviderForEveryID() {
        // All 8 providers have implementations now (closes #30).
        for id in GenAIProviderID.allCases {
            let p = LLMProviderFactory.create(
                providerID: id, meta: ProviderMeta(apiKey: "k"), model: ModelMeta(name: "x")
            )
            XCTAssertNotNil(p, "factory should produce a provider for \(id)")
        }
    }
}

final class AIGenerateContinuationTests: XCTestCase {
    func testContinuationPromptIncludesPriorReply() {
        let p = AIGeneratePane.continuationPrompt(from: "Once upon a time,")
        XCTAssertTrue(p.contains("Once upon a time,"), "prior reply must be quoted: \(p)")
    }

    func testContinuationPromptInstructsNoRepeat() {
        let p = AIGeneratePane.continuationPrompt(from: "x")
        XCTAssertTrue(p.localizedCaseInsensitiveContains("do not repeat"))
    }

    func testContinuationPromptTrimsSurroundingWhitespace() {
        let p = AIGeneratePane.continuationPrompt(from: "\n\n  hello world  \n\n")
        // The trimmed body sits on its own line — no leading/trailing whitespace inside it.
        XCTAssertTrue(p.contains("\nhello world"))
        XCTAssertFalse(p.contains("hello world  "))
    }
}
