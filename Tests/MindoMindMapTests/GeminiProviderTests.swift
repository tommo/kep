import XCTest
import MindoGenAI

final class GeminiProviderTests: XCTestCase {

    func testRequestBodyMatchesGeminiShape() throws {
        let input = LLMInput(
            providerID: GenAIProviderID.gemini.rawValue,
            model: "gemini-2.5-pro",
            text: "Hello",
            temperature: 0.4,
            maxTokens: 800,
            isStreaming: false
        )
        let body = GeminiProvider.makeBody(input)
        // Top-level keys.
        XCTAssertNotNil(body["contents"])
        XCTAssertNotNil(body["generationConfig"])
        // contents → user → text.
        let contents = body["contents"] as? [[String: Any]]
        XCTAssertEqual(contents?.first?["role"] as? String, "user")
        let parts = contents?.first?["parts"] as? [[String: Any]]
        XCTAssertEqual(parts?.first?["text"] as? String, "Hello")
        // generationConfig → temperature + maxOutputTokens.
        let gc = body["generationConfig"] as? [String: Any]
        XCTAssertEqual(gc?["maxOutputTokens"] as? Int, 800)
    }

    func testParsePredictResponseExtractsContent() throws {
        let json = """
        {
          "candidates": [{
            "content": {"role":"model","parts":[{"text":"Hi"},{"text":" there"}]},
            "finishReason":"STOP"
          }],
          "usageMetadata": {"candidatesTokenCount": 4}
        }
        """.data(using: .utf8)!
        let partial = try GeminiProvider.parsePredictResponse(json)
        XCTAssertEqual(partial.text, "Hi there")
        XCTAssertEqual(partial.outputTokens, 4)
        XCTAssertTrue(partial.isStop)
    }

    func testParsePredictResponseSurfacesAPIError() {
        let json = #"{"error":{"message":"missing api key"}}"#.data(using: .utf8)!
        XCTAssertThrowsError(try GeminiProvider.parsePredictResponse(json)) { error in
            guard case LLMError.decoding(let msg) = error else {
                XCTFail("expected .decoding got \(error)"); return
            }
            XCTAssertEqual(msg, "missing api key")
        }
    }

    func testParseStreamEventExtractsDelta() {
        let json = #"{"candidates":[{"content":{"role":"model","parts":[{"text":"chunk"}]}}]}"#
        let partial = GeminiProvider.parseStreamEvent(json)
        XCTAssertEqual(partial?.text, "chunk")
        XCTAssertFalse(partial?.isStop ?? true)
    }

    func testParseStreamEventDetectsFinishReason() {
        let json = #"{"candidates":[{"content":{"parts":[]},"finishReason":"STOP"}]}"#
        let partial = GeminiProvider.parseStreamEvent(json)
        XCTAssertNotNil(partial)
        XCTAssertTrue(partial?.isStop ?? false)
    }

    func testFactoryRoutesGeminiToGeminiProvider() {
        let p = LLMProviderFactory.create(
            providerID: .gemini,
            meta: ProviderMeta(apiKey: "k", endpoint: ""),
            model: ModelMeta(name: "gemini-2.5-pro")
        )
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.providerID, .gemini)
        XCTAssertTrue(p is GeminiProvider)
    }
}
