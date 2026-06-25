import XCTest
import AppKit
import KepBase
import KepModel
@testable import KepMindMap

@MainActor
final class MindMapNavigationTests: XCTestCase {

    func testOutlineFromMindMapEncodesIndexPaths() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        _ = a.addChild(text: "A1")
        _ = a.addChild(text: "A2")
        _ = root.addChild(text: "B")

        let items = Outline.fromMindMap(map)
        XCTAssertEqual(items.map(\.target), ["", "0", "0/0", "0/1", "1"])
    }

    func testNavigateSelectsTargetTopic() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let a = root.addChild(text: "A")
        let a1 = a.addChild(text: "A1")
        _ = a.addChild(text: "A2")
        let b = root.addChild(text: "B")
        _ = b

        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        view.navigate(to: "0/0")
        XCTAssertTrue(view.selectedElement?.topic === a1)

        view.navigate(to: "1")
        XCTAssertTrue(view.selectedElement?.topic === b)

        view.navigate(to: "")
        XCTAssertTrue(view.selectedElement?.topic === root)
    }

    func testInvalidPathDoesNotCrash() {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 600, height: 400))

        view.navigate(to: "999")
        view.navigate(to: "0/9")
        view.navigate(to: "junk/0")
        // Selection stays at whatever was set previously; no crash.
        XCTAssertNotNil(view)
    }
}
