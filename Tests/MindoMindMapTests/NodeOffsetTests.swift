import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Per-node manual offset (⌥-drag): the node and its subtree shift by
/// (offsetX, offsetY) on top of the auto-layout, it persists in the .mmd, and
/// can be reset.
@MainActor
final class NodeOffsetTests: XCTestCase {

    private func make() -> (MindMapView, root: Topic, a: Topic, a1: Topic) {
        let map = MindMap()
        let root = Topic(text: "R"); map.root = root
        let a = root.addChild(text: "A"); a.setAttribute(TopicAttribute.leftSide, "false")
        let a1 = a.addChild(text: "A1"); a1.setAttribute(TopicAttribute.leftSide, "false")
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        return (view, root, a, a1)
    }

    func testOffsetShiftsNodeAndSubtreeRelativeToRoot() {
        let (view, root, a, a1) = make()
        func rel(_ t: Topic) -> CGPoint {
            let f = view.element(forTopic: t)!.frame
            let r = view.element(forTopic: root)!.frame
            return CGPoint(x: f.midX - r.midX, y: f.midY - r.midY)
        }
        let aBefore = rel(a), childBefore = rel(a1)

        a.setAttribute(TopicAttribute.offsetX, "40")
        a.setAttribute(TopicAttribute.offsetY, "25")
        view.rebuildElementsPublic()

        let aAfter = rel(a), childAfter = rel(a1)
        XCTAssertEqual(aAfter.x, aBefore.x + 40, accuracy: 1, "node shifted right by offsetX")
        XCTAssertEqual(aAfter.y, aBefore.y + 25, accuracy: 1, "node shifted down by offsetY")
        XCTAssertEqual(childAfter.x, childBefore.x + 40, accuracy: 1, "subtree moved with it (x)")
        XCTAssertEqual(childAfter.y, childBefore.y + 25, accuracy: 1, "subtree moved with it (y)")
    }

    func testManualOffsetReadsAttributes() {
        let (view, _, a, _) = make()
        a.setAttribute(TopicAttribute.offsetX, "12.5")
        a.setAttribute(TopicAttribute.offsetY, "-8")
        view.rebuildElementsPublic()
        XCTAssertEqual(view.element(forTopic: a)!.manualOffset, CGPoint(x: 12.5, y: -8))
    }

    func testResetOffsetClearsIt() {
        let (view, _, a, _) = make()
        a.setAttribute(TopicAttribute.offsetX, "40")
        a.setAttribute(TopicAttribute.offsetY, "25")
        view.rebuildElementsPublic()
        let item = NSMenuItem(); item.representedObject = view.element(forTopic: a)
        view.contextResetOffset(item)
        XCTAssertNil(a.attribute(TopicAttribute.offsetX))
        XCTAssertNil(a.attribute(TopicAttribute.offsetY))
        XCTAssertEqual(view.element(forTopic: a)!.manualOffset, .zero)
    }

    func testOffsetPersistsThroughMmd() throws {
        let map = MindMap()
        let root = Topic(text: "R"); map.root = root
        let a = root.addChild(text: "A")
        a.setAttribute(TopicAttribute.offsetX, "40.0")
        a.setAttribute(TopicAttribute.offsetY, "-12.5")
        let reloaded = try MindMap(text: map.write())
        let ra = reloaded.root!.children[0]
        XCTAssertEqual(ra.attribute(TopicAttribute.offsetX), "40.0")
        XCTAssertEqual(ra.attribute(TopicAttribute.offsetY), "-12.5")
    }
}
