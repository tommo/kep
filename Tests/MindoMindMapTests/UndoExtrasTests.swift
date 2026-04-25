import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

@MainActor
final class UndoExtrasTests: XCTestCase {

    private func makeView() -> (MindMapView, Topic, UndoManager) {
        let map = MindMap()
        let root = Topic(text: "Root")
        map.root = root
        let (view, mgr) = makeHeadlessMindMap(map: map)
        return (view, root, mgr)
    }

    func testSetExtraIsUndoable() {
        let (view, topic, mgr) = makeView()
        XCTAssertNil(topic.extra(.note))
        view.undoableSetExtra(topic, .note, value: ExtraNote(text: "Hello"))
        XCTAssertEqual((topic.extra(.note) as? ExtraNote)?.text, "Hello")
        mgr.undo()
        XCTAssertNil(topic.extra(.note))
        mgr.redo()
        XCTAssertEqual((topic.extra(.note) as? ExtraNote)?.text, "Hello")
    }

    func testReplaceExtraIsUndoable() {
        let (view, topic, mgr) = makeView()
        view.undoableSetExtra(topic, .link, value: ExtraLink(uri: "https://a"))
        view.undoableSetExtra(topic, .link, value: ExtraLink(uri: "https://b"))
        XCTAssertEqual((topic.extra(.link) as? ExtraLink)?.uri, "https://b")
        mgr.undo()
        XCTAssertEqual((topic.extra(.link) as? ExtraLink)?.uri, "https://a")
        mgr.undo()
        XCTAssertNil(topic.extra(.link))
    }

    func testRemoveExtraIsUndoable() {
        let (view, topic, mgr) = makeView()
        view.undoableSetExtra(topic, .file, value: ExtraFile(uri: "/tmp/x"))
        view.undoableSetExtra(topic, .file, value: nil)
        XCTAssertNil(topic.extra(.file))
        mgr.undo()
        XCTAssertEqual((topic.extra(.file) as? ExtraFile)?.uri, "/tmp/x")
    }
}
