import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// M1 — topic-to-topic jump links: create (stamp UID + ExtraTopic) and follow
/// (click the badge → select + reveal the target). The model + badge rendering
/// already existed; this covers the create + navigate wiring that was missing.
@MainActor
final class TopicJumpLinkTests: XCTestCase {

    private func makeView() -> (MindMapView, root: Topic, a: Topic, b: Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A")
        let b = root.addChild(text: "B\nsecond line")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        return (view, root, a, b)
    }

    func testLinkStampsUIDAndExtra() {
        let (view, _, a, b) = makeView()
        let uid = view.undoableLinkTopic(a, to: b)
        XCTAssertFalse(uid.isEmpty)
        XCTAssertEqual(b.attribute(ExtraTopic.topicUidAttr), uid, "target carries the stable UID")
        XCTAssertEqual(a.extra(.topic)?.value, uid, "source's ExtraTopic points at the target UID")
    }

    func testEnsureUIDIsStableAndReused() {
        let (view, _, _, b) = makeView()
        let first = view.ensureTopicUID(b)
        let second = view.ensureTopicUID(b)
        XCTAssertEqual(first, second, "a topic keeps the same UID across calls")
        // Linking a second source reuses the existing target UID.
        let (_, _, a2, _) = makeView()
        // (different map, but linking within the same map reuses) — verify reuse
        // by linking another node in THIS map:
        let c = b.parent!.addChild(text: "C")
        let uid = view.undoableLinkTopic(c, to: b)
        XCTAssertEqual(uid, first, "a second link to the same target reuses its UID")
        _ = a2
    }

    func testFollowSelectsAndIsResolvable() {
        let (view, _, a, b) = makeView()
        let uid = view.undoableLinkTopic(a, to: b)
        // Start with A selected, then follow A's link → B becomes selected.
        view.selectElement(view.element(forTopic: a))
        view.followTopicLink(uid: uid)
        XCTAssertTrue(view.selectedElement?.topic === b, "following the link selects the target")
        XCTAssertTrue(view.mindMap?.findTopic(uid: uid) === b, "UID resolves back to the target")
    }

    func testTopicTapNavigatesToTarget() {
        let (view, _, a, b) = makeView()
        view.undoableLinkTopic(a, to: b)
        view.selectElement(view.element(forTopic: a))
        // Simulate clicking A's topic-jump badge.
        view.handleExtraTap(on: view.element(forTopic: a)!, type: .topic)
        XCTAssertTrue(view.selectedElement?.topic === b)
    }

    func testFollowUnknownUIDIsNoop() {
        let (view, _, a, _) = makeView()
        view.selectElement(view.element(forTopic: a))
        view.followTopicLink(uid: "does-not-exist")
        XCTAssertTrue(view.selectedElement?.topic === a, "selection unchanged when the UID resolves to nothing")
    }

    func testRemoveTopicLink() {
        let (view, _, a, b) = makeView()
        view.undoableLinkTopic(a, to: b)
        XCTAssertNotNil(a.extra(.topic))
        view.undoableSetExtra(a, .topic, value: nil)
        XCTAssertNil(a.extra(.topic), "removing the link drops the ExtraTopic")
        // The target keeps its (reusable) UID — harmless.
        XCTAssertNotNil(b.attribute(ExtraTopic.topicUidAttr))
    }

    func testMenuLabelUsesFirstLine() {
        XCTAssertEqual(TopicLinkPayload.label(for: Topic(text: "B\nsecond line")), "B")
        XCTAssertEqual(TopicLinkPayload.label(for: Topic(text: "   ")), "(untitled)")
    }
}
