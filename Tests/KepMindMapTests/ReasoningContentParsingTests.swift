import XCTest
import Foundation
@testable import KepGenAI

/// Reasoning models (deepseek-reasoner / -v4-flash) put output in
/// `reasoning_content` with `content` empty — the parser must surface it so
/// replies aren't silently dropped (the "no response, no error" bug).
final class ReasoningContentParsingTests: XCTestCase {

    func testStreamEventPrefersContent() {
        let p = OpenAICompatibleProvider.parseStreamEvent(#"{"choices":[{"delta":{"content":"Hello"}}]}"#)
        XCTAssertEqual(p?.text, "Hello")
    }

    func testStreamEventFallsBackToReasoning() {
        let p = OpenAICompatibleProvider.parseStreamEvent(
            #"{"choices":[{"delta":{"content":"","reasoning_content":"thinking..."}}]}"#)
        XCTAssertEqual(p?.text, "thinking...")
    }

    func testPredictPrefersContent() throws {
        let data = #"{"choices":[{"message":{"content":"Answer","reasoning_content":"why"}}]}"#.data(using: .utf8)!
        XCTAssertEqual(try OpenAICompatibleProvider.parsePredictResponse(data).text, "Answer")
    }

    func testPredictFallsBackToReasoning() throws {
        let data = #"{"choices":[{"message":{"content":"","reasoning_content":"the reasoning"}}]}"#.data(using: .utf8)!
        XCTAssertEqual(try OpenAICompatibleProvider.parsePredictResponse(data).text, "the reasoning")
    }
}
