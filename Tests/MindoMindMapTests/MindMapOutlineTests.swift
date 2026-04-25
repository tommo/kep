import XCTest
import MindoBase
import MindoModel
@testable import MindoMindMap

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

    func testEmptyMapProducesNothing() {
        let map = MindMap()
        XCTAssertTrue(Outline.fromMindMap(map).isEmpty)
    }
}
