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
        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let mgr = UndoManager()
        // With the default groupsByEvent=true, NSUndoManager wraps all
        // registrations made within one runloop pass into a single group
        // — that would mean a single mgr.undo() rolls back every test op
        // at once. Disable so each registration is its own group.
        mgr.groupsByEvent = false
        view.injectedUndoManager = mgr
        view.display(map: map)
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
