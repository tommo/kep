import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Build a real tree through the UI, then walk it with the arrow keys,
/// asserting the selected topic after every keystroke. Navigation is tested
/// on a tree that was actually constructed by user gestures (real elements,
/// real layout) rather than a synthetic fixture.
@MainActor
final class MindMapBuildAndNavigateScenarioTests: XCTestCase {

    private func makeHarness() throws -> WindowedMindMap {
        let map = MindMap()
        map.root = Topic(text: "Root")
        let h = WindowedMindMap(map: map)
        h.view.selectElement(h.view.element(forTopic: map.root!))
        h.view.beginInlineEdit(on: h.view.element(forTopic: map.root!)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        try XCTSkipIf(!ok, "headless host can't host a field editor")
        return h
    }

    private func type(_ h: WindowedMindMap, _ s: String) { for ch in s { h.sendKey(String(ch)) } }
    private func sel(_ h: WindowedMindMap) -> String? { h.view.selectedElement?.topic.text }

    func testBuildThenArrowWalk() throws {
        let h = try makeHarness()
        let root = h.view.mindMap!.root!

        // Build:  Root ─ A ─ A1, A2
        //              ─ B
        h.view.selectElement(h.view.element(forTopic: root))
        h.sendKey("\t"); type(h, "A"); h.sendKey("\r")     // child A, finish (on A)
        h.sendKey("\r"); type(h, "B"); h.sendKey("\r")     // sibling B, finish (on B)
        h.click(topic: root.children[0])                    // select A
        h.sendKey("\t"); type(h, "A1"); h.sendKey("\r")    // child A1, finish
        h.sendKey("\r"); type(h, "A2"); h.sendKey("\r")    // sibling A2, finish

        let a = root.children[0], b = root.children[1]
        XCTAssertEqual(root.children.map(\.text), ["A", "B"])
        XCTAssertEqual(a.children.map(\.text), ["A1", "A2"])

        // All these topics are on the right side (root child index 0 is right,
        // and the sibling inherits the side) so Right = inward, Left = outward.
        XCTAssertFalse(h.view.element(forTopic: a)!.isLeftSide, "fixture assumes right-side layout")

        // Walk from the root.
        h.view.selectElement(h.view.element(forTopic: root))
        XCTAssertEqual(sel(h), "Root")
        h.sendArrow(NSRightArrowFunctionKey);  XCTAssertEqual(sel(h), "A",  "Root → first child")
        h.sendArrow(NSDownArrowFunctionKey);   XCTAssertEqual(sel(h), "B",  "A ↓ next sibling")
        h.sendArrow(NSUpArrowFunctionKey);     XCTAssertEqual(sel(h), "A",  "B ↑ back to A")
        h.sendArrow(NSRightArrowFunctionKey);  XCTAssertEqual(sel(h), "A1", "A → first child")
        h.sendArrow(NSDownArrowFunctionKey);   XCTAssertEqual(sel(h), "A2", "A1 ↓ A2")
        h.sendArrow(NSLeftArrowFunctionKey);   XCTAssertEqual(sel(h), "A",  "A2 ← back to parent A")
        h.sendArrow(NSLeftArrowFunctionKey);   XCTAssertEqual(sel(h), "Root", "A ← back to Root")
        _ = b
    }

    func testBuildThenDeleteUpdatesSelectionAndTree() throws {
        let h = try makeHarness()
        let root = h.view.mindMap!.root!
        h.view.selectElement(h.view.element(forTopic: root))
        h.sendKey("\t"); type(h, "A"); h.sendKey("\r")
        h.sendKey("\r"); type(h, "B"); h.sendKey("\r")
        h.sendKey("\r"); type(h, "C"); h.sendKey("\r")
        XCTAssertEqual(root.children.map(\.text), ["A", "B", "C"])

        // Select B and delete it.
        h.click(topic: root.children[1])
        XCTAssertEqual(sel(h), "B")
        h.sendKey("\u{7F}")                      // Delete
        XCTAssertEqual(root.children.map(\.text), ["A", "C"], "B removed")
        XCTAssertEqual(sel(h), "C", "selection stays at the current level — the sibling after B")
        // And the keyboard still works afterwards: Up from C lands on A.
        h.sendArrow(NSUpArrowFunctionKey)
        XCTAssertEqual(sel(h), "A", "navigation still works after delete")
    }
}
