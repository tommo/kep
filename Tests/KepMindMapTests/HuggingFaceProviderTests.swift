import XCTest
import KepGenAI

final class HuggingFaceProviderTests: XCTestCase {

    func testRequestBodyShape() {
        let input = LLMInput(
            providerID: GenAIProviderID.huggingFace.rawValue,
            model: "mistralai/Mistral-7B-Instruct-v0.3",
            text: "Tell me a joke",
            temperature: 0.5,
            maxTokens: 256,
            isStreaming: true
        )
        let body = HuggingFaceProvider.makeBody(input, streaming: true)
        XCTAssertEqual(body["inputs"] as? String, "Tell me a joke")
        let params = body["parameters"] as? [String: Any]
        XCTAssertEqual(params?["max_new_tokens"] as? Int, 256)
        XCTAssertEqual(params?["return_full_text"] as? Bool, false)
        XCTAssertEqual(params?["stream"] as? Bool, true)
    }

    func testNonStreamingBodyOmitsStreamFlag() {
        let input = LLMInput(
            providerID: GenAIProviderID.huggingFace.rawValue,
            model: "x", text: "y"
        )
        let body = HuggingFaceProvider.makeBody(input, streaming: false)
        let params = body["parameters"] as? [String: Any]
        XCTAssertNil(params?["stream"])
    }

    func testParsePredictResponseFromArray() throws {
        let json = #"[{"generated_text":"the answer"}]"#.data(using: .utf8)!
        let p = try HuggingFaceProvider.parsePredictResponse(json)
        XCTAssertEqual(p.text, "the answer")
        XCTAssertTrue(p.isStop)
    }

    func testParsePredictResponseFromSingleObject() throws {
        let json = #"{"generated_text":"single"}"#.data(using: .utf8)!
        let p = try HuggingFaceProvider.parsePredictResponse(json)
        XCTAssertEqual(p.text, "single")
    }

    func testParsePredictResponseSurfacesError() {
        let json = #"{"error":"model not found"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try HuggingFaceProvider.parsePredictResponse(json)) { err in
            guard case LLMError.decoding(let msg) = err else { XCTFail("\(err)"); return }
            XCTAssertEqual(msg, "model not found")
        }
    }

    func testParseStreamEventExtractsTokenText() {
        let json = #"{"token":{"id":1,"text":"hello","special":false},"generated_text":null}"#
        let p = HuggingFaceProvider.parseStreamEvent(json)
        XCTAssertEqual(p?.text, "hello")
        XCTAssertFalse(p?.isStop ?? true)
    }

    func testParseStreamEventDetectsFinalGenerated() {
        let json = #"{"token":{"id":2,"text":"!","special":false},"generated_text":"hello!"}"#
        let p = HuggingFaceProvider.parseStreamEvent(json)
        XCTAssertNotNil(p)
        XCTAssertTrue(p?.isStop ?? false)
    }

    func testParseStreamEventDropsSpecialTokens() {
        let json = #"{"token":{"id":3,"text":"<EOS>","special":true},"generated_text":null}"#
        let p = HuggingFaceProvider.parseStreamEvent(json)
        // Special non-final tokens emit empty text so they don't pollute output.
        XCTAssertEqual(p?.text, "")
    }

    func testFactoryRoutesHuggingFaceAndChatGLM() {
        let hf = LLMProviderFactory.create(
            providerID: .huggingFace,
            meta: ProviderMeta(apiKey: "k", endpoint: ""),
            model: ModelMeta(name: "x")
        )
        XCTAssertNotNil(hf)
        XCTAssertEqual(hf?.providerID, .huggingFace)
        XCTAssertTrue(hf is HuggingFaceProvider)

        let glm = LLMProviderFactory.create(
            providerID: .chatGLM,
            meta: ProviderMeta(apiKey: "k", endpoint: ""),
            model: ModelMeta(name: "glm-4")
        )
        XCTAssertNotNil(glm)
        XCTAssertEqual(glm?.providerID, .chatGLM)
        XCTAssertTrue(glm is ChatGLMProvider)
    }
}
