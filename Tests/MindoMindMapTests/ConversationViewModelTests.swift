import XCTest
@testable import MindoGenAI

@MainActor
final class ConversationViewModelTests: XCTestCase {

    func testCanSendGating() {
        let vm = ConversationViewModel(systemPrompt: "S")
        XCTAssertFalse(vm.canSend, "empty draft → can't send")
        vm.draft = "   "
        XCTAssertFalse(vm.canSend, "whitespace-only → can't send")
        vm.draft = "hello"
        XCTAssertTrue(vm.canSend)
        vm.isRunning = true
        XCTAssertFalse(vm.canSend, "in-flight → can't send")
    }

    func testSetContextUpdatesConversation() {
        let vm = ConversationViewModel(systemPrompt: "S", contextBlock: "old")
        XCTAssertEqual(vm.conversation.contextBlock, "old")
        vm.setContext("new")
        XCTAssertEqual(vm.conversation.contextBlock, "new")
    }

    func testClearEmptiesTurns() {
        let vm = ConversationViewModel(systemPrompt: "S")
        vm.conversation.addUser("q")
        vm.conversation.addAssistant("a")
        XCTAssertEqual(vm.conversation.turns.count, 2)
        vm.clear()
        XCTAssertTrue(vm.conversation.turns.isEmpty)
    }

    func testLastAssistantText() {
        let vm = ConversationViewModel(systemPrompt: "S")
        vm.conversation.addUser("q")
        XCTAssertNil(vm.lastAssistantText)
        vm.conversation.addAssistant("the answer")
        XCTAssertEqual(vm.lastAssistantText, "the answer")
    }
}
