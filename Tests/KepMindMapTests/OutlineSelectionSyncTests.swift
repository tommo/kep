import XCTest
import AppKit
import KepModel
import KepBase
@testable import KepMindMap

/// The graph→outline selection sync hinges on `MindMapView.selectedOutlinePath`
/// producing the same index-path scheme as `Outline.fromMindMap`'s row targets.
@MainActor
final class OutlineSelectionSyncTests: XCTestCase {

    private func sampleMap() -> (MindMap, root: Topic, a: Topic, a1: Topic, b: Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A")
        let a1 = a.addChild(text: "A1")
        let b = root.addChild(text: "B")
        return (map, root, a, a1, b)
    }

    func testSelectedPathMatchesOutlineTargets() {
        let (map, root, a, a1, b) = sampleMap()
        let view = makeHeadlessMindMap(map: map)
        // Outline targets for reference.
        let items = Outline.fromMindMap(map)
        func target(_ title: String) -> String { items.first { $0.title == title }!.target }

        view.selectElement(view.element(forTopic: root))
        XCTAssertEqual(view.selectedOutlinePath, target("Root"))   // ""
        XCTAssertEqual(view.selectedOutlinePath, "")

        view.selectElement(view.element(forTopic: a))
        XCTAssertEqual(view.selectedOutlinePath, target("A"))      // "0"
        XCTAssertEqual(view.selectedOutlinePath, "0")

        view.selectElement(view.element(forTopic: a1))
        XCTAssertEqual(view.selectedOutlinePath, target("A1"))     // "0/0"
        XCTAssertEqual(view.selectedOutlinePath, "0/0")

        view.selectElement(view.element(forTopic: b))
        XCTAssertEqual(view.selectedOutlinePath, target("B"))      // "1"
        XCTAssertEqual(view.selectedOutlinePath, "1")
    }

    func testNoSelectionIsNilPath() {
        let (map, _, _, _, _) = sampleMap()
        let view = makeHeadlessMindMap(map: map)
        view.selectElement(nil)
        XCTAssertNil(view.selectedOutlinePath)
    }

    func testNavigateThenSelectedPathRoundTrips() {
        // outline → graph: navigating to a target selects that topic, and the
        // reported path equals the target (so the highlight stays consistent).
        let (map, _, _, _, _) = sampleMap()
        let view = makeHeadlessMindMap(map: map)
        for item in Outline.fromMindMap(map) {
            view.navigate(to: item.target)
            XCTAssertEqual(view.selectedOutlinePath, item.target,
                           "navigating to \(item.target) should select that topic")
        }
    }
}
