import XCTest
import KepBase
import KepModel
@testable import KepMindMap

final class MindMapOutlineTests: XCTestCase {

    func testWalkProducesPreOrderItems() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "Alpha")
        _ = a.addChild(text: "A1")
        _ = a.addChild(text: "A2")
        let b = root.addChild(text: "Beta")
        _ = b.addChild(text: "B1")

        let items = Outline.fromMindMap(map)
        XCTAssertEqual(items.map(\.title), ["Root", "Alpha", "A1", "A2", "Beta", "B1"])
        XCTAssertEqual(items.map(\.depth), [1, 2, 3, 3, 2, 3])
    }

    func testOutlineCarriesTypedPropertyMarkers() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let task = root.addChild(text: "Task")
        task.setProperty("priority", .number(1))
        task.setProperty("done", .checkbox(true))
        let plain = root.addChild(text: "Plain")

        let items = Outline.fromMindMap(map)
        let taskItem = items.first { $0.title == "Task" }!
        // priority(1) → red flag, done(true) → green check; stable order.
        XCTAssertEqual(taskItem.markers.map(\.tint), [.priority(1), .done])
        XCTAssertTrue(items.first { $0.title == "Plain" }!.markers.isEmpty)
        XCTAssertTrue(items.first { $0.title == "Root" }!.markers.isEmpty)
        _ = plain
    }

    func testOutlineShowsNoteIndicator() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let noted = root.addChild(text: "Has note")
        noted.setExtra(ExtraNote(text: "some detail"))
        _ = root.addChild(text: "Plain")

        let items = Outline.fromMindMap(map)
        XCTAssertEqual(items.first { $0.title == "Has note" }!.markers.map(\.symbolName), ["note.text"])
        XCTAssertTrue(items.first { $0.title == "Plain" }!.markers.isEmpty)
    }

    func testCollapsedNodeHidesDescendantsButKeepsChevron() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "Alpha")
        _ = a.addChild(text: "A1")
        _ = a.addChild(text: "A2")
        _ = root.addChild(text: "Beta")
        a.setAttribute(TopicAttribute.collapsed, "true")

        let items = Outline.fromMindMap(map)
        // Alpha's children are omitted; Alpha still appears, marked collapsed.
        XCTAssertEqual(items.map(\.title), ["Root", "Alpha", "Beta"])
        let alpha = items.first { $0.title == "Alpha" }!
        XCTAssertTrue(alpha.hasChildren)
        XCTAssertTrue(alpha.isCollapsed)
        XCTAssertFalse(items.first { $0.title == "Beta" }!.hasChildren)
    }

    func testEmptyMapProducesNothing() {
        let map = MindMap()
        XCTAssertTrue(Outline.fromMindMap(map).isEmpty)
    }
}
