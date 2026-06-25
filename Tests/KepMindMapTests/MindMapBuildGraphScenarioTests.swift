import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// End-to-end "build a real graph" scenario: drive the editor exactly as a
/// user would (real key/mouse events) and, after every step, compare the WHOLE
/// tree + selection + editor state against expectation. This is how the
/// "finish editing → cursor warped to another node" class of bugs surfaces —
/// the mid-results are checked, not just the final tree.
@MainActor
final class MindMapBuildGraphScenarioTests: XCTestCase {

    /// Indented text snapshot of the whole tree — the thing we diff against
    /// expectation at each checkpoint.
    private func tree(_ t: Topic, _ depth: Int = 0) -> String {
        var s = String(repeating: "  ", count: depth) + t.text + "\n"
        for c in t.children { s += tree(c, depth + 1) }
        return s
    }

    private func makeHarness() throws -> WindowedMindMap {
        let map = MindMap()
        map.root = Topic(text: "root")
        let h = WindowedMindMap(map: map)
        h.view.selectElement(h.view.element(forTopic: map.root!))
        h.view.beginInlineEdit(on: h.view.element(forTopic: map.root!)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        try XCTSkipIf(!ok, "headless host can't host a field editor")
        return h
    }

    private func type(_ h: WindowedMindMap, _ s: String) { for ch in s { h.sendKey(String(ch)) } }

    /// What the user is currently editing (field text), or nil.
    private func editing(_ h: WindowedMindMap) -> String? { h.editorText }
    private func selectedText(_ h: WindowedMindMap) -> String? { h.view.selectedElement?.topic.text }

    // MARK: - Full keyboard build, checking every mid-result

    func testBuildGraphStepByStep() throws {
        let h = try makeHarness()
        let root = h.view.mindMap!.root!

        // 1. Edit the root, type its title; Return finishes (stays on root).
        h.click(topic: root, clickCount: 2)
        type(h, "Project")
        XCTAssertEqual(editing(h), "Project")
        h.sendKey("\r")
        XCTAssertEqual(root.text, "Project")
        XCTAssertNil(editing(h), "Return finished the edit — no node created, no warp")
        XCTAssertTrue(selectedText(h) == "Project", "still on root")

        // 2. Tab on the SELECTED root → a child, editing it.
        h.sendKey("\t")
        XCTAssertEqual(root.children.count, 1)
        XCTAssertTrue(h.view.inlineEditTarget === root.children[0], "editing the NEW child")
        type(h, "Goals")
        h.sendKey("\r")                       // finish; stay on Goals
        let goals = root.children[0]
        XCTAssertEqual(goals.text, "Goals")
        XCTAssertTrue(selectedText(h) == "Goals")

        // 3. Tab → child of Goals, name it "G1", finish.
        h.sendKey("\t")
        type(h, "G1")
        h.sendKey("\r")
        XCTAssertEqual(goals.children.map(\.text), ["G1"])
        XCTAssertTrue(selectedText(h) == "G1")

        // 4. Return on the SELECTED G1 → a sibling under Goals (adjacent),
        //    name it "G2", finish.
        h.sendKey("\r")
        XCTAssertEqual(goals.children.count, 2, "sibling created under Goals")
        XCTAssertTrue(h.view.inlineEditTarget?.parent === goals, "sibling stayed under Goals — no warp")
        type(h, "G2")
        h.sendKey("\r")
        XCTAssertEqual(goals.children.map(\.text), ["G1", "G2"])

        // Final structure must be exactly:
        let expected = """
        Project
          Goals
            G1
            G2

        """
        XCTAssertEqual(tree(root), expected, "graph matches the expected structure")
    }

    // MARK: - The reported bug: finishing an edit should not warp the cursor

    func testFinishEditingKeepsSelectionPredictable() throws {
        // Build root → A, B, C as siblings.
        let h = try makeHarness()
        let root = h.view.mindMap!.root!
        let a = root.addChild(text: "A")
        let b = root.addChild(text: "B")
        let c = root.addChild(text: "C")
        h.view.rebuildElementsPublic()

        // Edit the MIDDLE node B, retype it, finish with Return.
        h.click(topic: b, clickCount: 2)
        type(h, "Beta")
        h.sendKey("\r")
        XCTAssertEqual(b.text, "Beta")
        XCTAssertNil(h.view.inlineEditor, "edit finished")
        XCTAssertTrue(selectedText(h) == "Beta",
                      "after finishing the edit the SAME node stays selected — no warp")
        XCTAssertEqual(root.children.map(\.text), ["A", "Beta", "C"], "neighbours untouched")
        _ = (a, c)
    }
}
