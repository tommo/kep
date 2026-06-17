import XCTest
import Foundation
@testable import MindoGenAI

final class ConversationTests: XCTestCase {

    // MARK: - Conversation model

    func testLLMMessagesIncludesSystemThenContextThenTurns() {
        var c = Conversation(systemPrompt: "SYS", contextBlock: "CTX")
        c.addUser("hello")
        c.addAssistant("hi")
        c.addUser("more")
        let msgs = c.llmMessages()
        XCTAssertEqual(msgs.map(\.role), [.system, .system, .user, .assistant, .user])
        XCTAssertEqual(msgs[0].content, "SYS")
        XCTAssertEqual(msgs[1].content, "CTX")
        XCTAssertEqual(msgs.last?.content, "more")
    }

    func testNoContextBlockOrSystemOmitsThem() {
        var c = Conversation(systemPrompt: "", contextBlock: nil)
        c.addUser("q")
        XCTAssertEqual(c.llmMessages().map(\.role), [.user])
    }

    func testHistoryLimitTrimsOldestVisibleTurns() {
        var c = Conversation(systemPrompt: "S", historyLimit: 2)
        c.addUser("1"); c.addAssistant("2"); c.addUser("3"); c.addAssistant("4")
        let msgs = c.llmMessages()
        // system + last 2 turns only
        XCTAssertEqual(msgs.map(\.content), ["S", "3", "4"])
        // but all 4 remain for display
        XCTAssertEqual(c.turns.count, 4)
    }

    func testAppendToLastAssistantStreams() {
        var c = Conversation(systemPrompt: "")
        c.addUser("q")
        c.appendToLastAssistant("Hel")
        c.appendToLastAssistant("lo")
        XCTAssertEqual(c.turns.last?.role, .assistant)
        XCTAssertEqual(c.turns.last?.content, "Hello")
        XCTAssertEqual(c.turns.filter { $0.role == .assistant }.count, 1)
    }

    func testEmptyTurnsDroppedFromWire() {
        var c = Conversation(systemPrompt: "S")
        c.addUser("q")
        c.addAssistant("")   // not yet streamed
        XCTAssertEqual(c.llmMessages().map(\.content), ["S", "q"])
    }

    // MARK: - LLMInput wire messages

    func testWireMessagesFallsBackToSingleUserTurn() {
        let input = LLMInput(providerID: "X", model: "m", text: "hi")
        XCTAssertEqual(input.wireMessages, [.user("hi")])
    }

    func testWireMessagesUsesExplicitConversation() {
        let convo: [ChatMessage] = [.system("s"), .user("u")]
        let input = LLMInput(providerID: "X", model: "m", text: "ignored", messages: convo)
        XCTAssertEqual(input.wireMessages, convo)
    }

    func testEmptyMessagesArrayFallsBack() {
        let input = LLMInput(providerID: "X", model: "m", text: "hi", messages: [])
        XCTAssertEqual(input.wireMessages, [.user("hi")])
    }

    // MARK: - Request body carries the full message array

    func testMakeRequestSerializesAllMessages() throws {
        let provider = DeepSeekProvider(
            meta: ProviderMeta(apiKey: "k", endpoint: GenAIProviderID.deepSeek.defaultEndpoint),
            model: ModelMeta(name: "deepseek-v4-flash")
        )
        let input = LLMInput(providerID: GenAIProviderID.deepSeek.rawValue, model: "deepseek-v4-flash",
                             text: "x", messages: [.system("be nice"), .user("hello"), .assistant("hi"), .user("bye")])
        let req = try provider.makeRequest(input, streaming: false)
        let body = try XCTUnwrap(req.httpBody)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let msgs = try XCTUnwrap(obj["messages"] as? [[String: String]])
        XCTAssertEqual(msgs.count, 4)
        XCTAssertEqual(msgs.first?["role"], "system")
        XCTAssertEqual(msgs.first?["content"], "be nice")
        XCTAssertEqual(msgs.last?["role"], "user")
        XCTAssertEqual(msgs.last?["content"], "bye")
    }
}
