import XCTest
import KepModel
@testable import KepMindMap

final class JumpArrowTests: XCTestCase {

    func testFindTopicByUIDLocatesTarget() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        a.setAttribute(ExtraTopic.topicUidAttr, "ABC123")
        let b = root.addChild(text: "B")

        XCTAssertTrue(map.findTopic(uid: "ABC123") === a)
        XCTAssertNil(map.findTopic(uid: "missing"))
        _ = b
    }

    /// A topic carrying an ExtraTopic should be considered "linked" — the
    /// drawing code uses the same lookup, so a smoke test of the lookup +
    /// extra type confirms the data wiring is right.
    func testTopicWithExtraTopicResolvesBackToTarget() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let target = root.addChild(text: "Target")
        target.setAttribute(ExtraTopic.topicUidAttr, "XYZ")
        let source = root.addChild(text: "Source")
        source.setExtra(ExtraTopic(topicUID: "XYZ"))

        XCTAssertTrue(source.extra(.topic) is ExtraTopic)
        let resolved = (source.extra(.topic) as? ExtraTopic).flatMap { map.findTopic(uid: $0.value) }
        XCTAssertTrue(resolved === target)
    }
}
