import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// Notes are peeked on hover (native tooltip) and the icon click just selects
/// the node so its note opens in the inspector — the old modal NSAlert popup
/// was removed. This covers the click → select behaviour.
@MainActor
final class NoteHoverTapTests: XCTestCase {

    private func makeView() -> (MindMapView, root: Topic, a: Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A")
        let v = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        return (v, root, a)
    }

    func testNoteTapSelectsNode() {
        let (v, root, a) = makeView()
        v.undoableSetExtra(a, .note, value: ExtraNote(text: "remember this"))
        // Start elsewhere so the select is observable.
        v.selectElement(v.element(forTopic: root))
        XCTAssertTrue(v.selectedElement?.topic === root)

        v.handleExtraTap(on: v.element(forTopic: a)!, type: .note)

        XCTAssertTrue(v.selectedElement?.topic === a,
                      "clicking the note icon selects its node (reveals it in the inspector)")
    }
}
