import XCTest
@testable import MindoModel

final class SupertagTests: XCTestCase {

    func testApplyStampsMissingFieldsWithTypedDefaults() {
        let t = Topic(text: "Plan")
        let task = SupertagCatalog.named("task")!
        let added = task.apply(to: t)
        XCTAssertEqual(Set(added), ["priority", "done"])
        XCTAssertEqual(t.property("priority"), .number(3))
        XCTAssertEqual(t.property("done"), .checkbox(false))
    }

    func testApplyIsNonDestructiveAndIdempotent() {
        let t = Topic(text: "Plan")
        t.setProperty("priority", .number(1))                 // pre-existing value
        let added = SupertagCatalog.named("Task")!.apply(to: t)
        XCTAssertEqual(added, ["done"])                        // priority kept, only done added
        XCTAssertEqual(t.property("priority"), .number(1))     // not clobbered
        // Applying again adds nothing.
        XCTAssertEqual(SupertagCatalog.named("Task")!.apply(to: t), [])
    }

    func testMissingKeysReportsWhatWouldBeAdded() {
        let t = Topic(text: "Plan")
        t.setProperty("done", .checkbox(true))
        XCTAssertEqual(SupertagCatalog.named("task")!.missingKeys(in: t), ["priority"])
    }

    func testNamedLookupIsCaseInsensitiveAndUnknownReturnsNil() {
        XCTAssertNotNil(SupertagCatalog.named("TRACKED"))
        XCTAssertNil(SupertagCatalog.named("nope"))
    }
}
