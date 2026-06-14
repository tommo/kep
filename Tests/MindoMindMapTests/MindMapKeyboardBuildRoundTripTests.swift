import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Build a multi-level mind map entirely through real key events, then prove
/// the interactively-built graph (a) serialises to `.mmd` and reparses to the
/// SAME structure, and (b) unwinds cleanly when the whole build is undone.
/// This joins three subsystems the per-feature tests only exercise in
/// isolation — the keyboard create/edit flow, the codec, and undo grouping —
/// which is where cross-cutting bugs (a stray child order, a lost edit, a
/// half-undone group) hide.
@MainActor
final class MindMapKeyboardBuildRoundTripTests: XCTestCase {

    /// Indented text snapshot of the whole tree — side attributes intentionally
    /// ignored so the assertion targets structure + order, the things a
    /// round-trip must preserve.
    private func tree(_ t: Topic, _ depth: Int = 0) -> String {
        var s = String(repeating: "  ", count: depth) + t.text + "\n"
        for c in t.children { s += tree(c, depth + 1) }
        return s
    }

    private func makeHarness() throws -> (WindowedMindMap, UndoManager) {
        let map = MindMap()
        map.root = Topic(text: "root")
        let h = WindowedMindMap(map: map)
        let mgr = UndoManager()
        mgr.groupsByEvent = false
        h.view.injectedUndoManager = mgr
        // Field-editor availability probe — headless CI can't host one.
        h.view.selectElement(h.view.element(forTopic: map.root!))
        h.view.beginInlineEdit(on: h.view.element(forTopic: map.root!)!)
        let ok = h.view.inlineEditor?.currentEditor() != nil
        h.view.cancelInlineEdit()
        try XCTSkipIf(!ok, "headless host can't host a field editor")
        return (h, mgr)
    }

    private func type(_ h: WindowedMindMap, _ s: String) { for ch in s { h.sendKey(String(ch)) } }

    /// Reposition the selection without the keyboard — arrow navigation has its
    /// own dedicated tests; here it would only add side-dependent fragility to
    /// a test about building + persistence.
    private func select(_ h: WindowedMindMap, _ topic: Topic) {
        h.view.selectElement(h.view.element(forTopic: topic))
    }

    // MARK: - Build → serialise → reparse

    func testKeyboardBuiltGraphSerialisesAndReloads() throws {
        let (h, _) = try makeHarness()
        let root = h.view.mindMap!.root!

        // root → "Plan" (double-click to edit, type, Return commits + stays).
        h.click(topic: root, clickCount: 2)
        type(h, "Plan"); h.sendKey("\r")
        XCTAssertEqual(root.text, "Plan")

        // Plan ▸ Research (Tab = child).
        h.sendKey("\t"); type(h, "Research"); h.sendKey("\r")
        let research = root.children[0]

        // Research ▸ Sources (Tab = child), then Notes (Return = sibling).
        h.sendKey("\t"); type(h, "Sources"); h.sendKey("\r")
        h.sendKey("\r"); type(h, "Notes"); h.sendKey("\r")
        XCTAssertEqual(research.children.map(\.text), ["Sources", "Notes"])

        // Back on Research, Return makes Design a sibling under Plan.
        select(h, research)
        h.sendKey("\r"); type(h, "Design"); h.sendKey("\r")
        XCTAssertEqual(root.children.map(\.text), ["Research", "Design"])

        // Design ▸ Mockups (Tab = child).
        h.sendKey("\t"); type(h, "Mockups"); h.sendKey("\r")

        let expected = """
        Plan
          Research
            Sources
            Notes
          Design
            Mockups

        """
        XCTAssertEqual(tree(root), expected, "interactively-built graph structure")

        // The whole point: a graph you built by hand must persist. Serialise to
        // the native .mmd text and reparse — the structure must come back byte
        // for byte (in the tree-snapshot sense).
        let text = h.view.mindMap!.write()
        let reloaded = try MindMap(text: text)
        XCTAssertEqual(tree(reloaded.root!), expected,
                       ".mmd round-trip preserves the keyboard-built structure")
    }

    // MARK: - Editing text must not strip rich media (codec × edit × media)

    /// A topic carrying a fill colour + a note keeps both when you retype its
    /// text with the keyboard AND when that edited map is serialised and
    /// reloaded. Catches the class of bug where the text edit (or the codec)
    /// silently drops attributes/extras — the user's "mixing codec, rich media"
    /// concern, exercised through the real inline-edit path rather than a bare
    /// codec round-trip.
    func testKeyboardTextEditPreservesRichMediaThroughRoundTrip() throws {
        let (h, _) = try makeHarness()
        let root = h.view.mindMap!.root!
        let task = root.addChild(text: "Task")
        task.setAttribute(TopicAttribute.fillColor, "#ffcc00")
        task.setExtra(ExtraNote(text: "remember this"))
        h.view.rebuildElementsPublic()

        // Retype the topic via the inline editor (double-click selects all, so
        // typing replaces "Task" wholesale), then commit.
        h.click(topic: task, clickCount: 2)
        type(h, "Done"); h.sendKey("\r")
        XCTAssertEqual(task.text, "Done", "text was replaced")
        XCTAssertEqual(task.attribute(TopicAttribute.fillColor), "#ffcc00",
                       "fill colour survives a text edit")
        XCTAssertEqual((task.extra(.note) as? ExtraNote)?.text, "remember this",
                       "note survives a text edit")

        // Serialise the edited map and reparse — the rich media must come back.
        let reloaded = try MindMap(text: h.view.mindMap!.write())
        guard let reTask = reloaded.root?.children.first else {
            return XCTFail("reloaded map lost the child topic")
        }
        XCTAssertEqual(reTask.text, "Done")
        XCTAssertEqual(reTask.attribute(TopicAttribute.fillColor), "#ffcc00",
                       "fill colour round-trips through .mmd")
        XCTAssertEqual((reTask.extra(.note) as? ExtraNote)?.text, "remember this",
                       "note round-trips through .mmd")
    }

    // MARK: - Undo unwinds the whole build

    func testUndoUnwindsEntireKeyboardBuild() throws {
        let (h, mgr) = try makeHarness()
        let root = h.view.mindMap!.root!

        h.click(topic: root, clickCount: 2)
        type(h, "Plan"); h.sendKey("\r")
        h.sendKey("\t"); type(h, "A"); h.sendKey("\r")     // child A
        h.sendKey("\r"); type(h, "B"); h.sendKey("\r")     // sibling B
        XCTAssertEqual(root.children.map(\.text), ["A", "B"])

        // Pop every undo group the build registered; the tree must return to a
        // childless root (no half-applied group left dangling).
        var guardCount = 0
        while mgr.canUndo && guardCount < 100 { mgr.undo(); guardCount += 1 }
        XCTAssertTrue(root.children.isEmpty,
                      "undoing the whole build leaves the root childless")
    }
}
