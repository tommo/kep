import XCTest
import AppKit
import KepModel
@testable import KepMindMap

@MainActor
final class ToggleDoneTests: XCTestCase {
    func testToggleDoneFlipsTaskProperty() {
        let map = MindMap(); let root = Topic(text: "Task"); map.root = root
        let view = makeHeadlessMindMap(map: map)
        let el = view.element(forTopic: root)!
        let item = NSMenuItem(); item.representedObject = el

        view.contextToggleDone(item)                       // none → done
        XCTAssertEqual(root.property(PropertyMarkers.doneKey), .checkbox(true))
        XCTAssertEqual(PropertyMarkers.markerRow(for: root).map(\.role), [.doneTrue])

        view.contextToggleDone(item)                       // done → not done
        XCTAssertEqual(root.property(PropertyMarkers.doneKey), .checkbox(false))
        XCTAssertEqual(PropertyMarkers.markerRow(for: root).map(\.role), [.doneFalse])
    }
}
