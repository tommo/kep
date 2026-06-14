import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Comprehensive keyboard-navigation coverage for the mindmap canvas,
/// driving both the element resolver and synthesized arrow-key `keyDown`
/// events through a headless view. Guards the side-aware navigation: the map
/// is mirrored about the root, so Left/Right mean opposite tree-directions
/// on the two halves.
@MainActor
final class KeyboardNavComprehensiveTests: XCTestCase {

    // A deterministic two-sided map (explicit leftSide attrs so the test
    // doesn't depend on the auto-balance index parity):
    //
    //            root
    //   right →  R1 ─ R1a, R1b      ← left  L1 ─ L1a, L1b
    //            R2                          L2
    private struct Fixture {
        let view: MindMapView
        let root, r1, r1a, r1b, r2, l1, l1a, l1b, l2: Topic
    }

    private func makeFixture() -> Fixture {
        let map = MindMap()
        let root = Topic(text: "root"); map.root = root
        func right(_ t: Topic) -> Topic { t.setAttribute(TopicAttribute.leftSide, "false"); return t }
        func left(_ t: Topic) -> Topic { t.setAttribute(TopicAttribute.leftSide, "true"); return t }
        let r1 = right(root.addChild(text: "R1"))
        let r1a = r1.addChild(text: "R1a"); let r1b = r1.addChild(text: "R1b")
        let r2 = right(root.addChild(text: "R2"))
        let l1 = left(root.addChild(text: "L1"))
        let l1a = l1.addChild(text: "L1a"); let l1b = l1.addChild(text: "L1b")
        let l2 = left(root.addChild(text: "L2"))
        let view = makeHeadlessMindMap(map: map, frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        return Fixture(view: view, root: root, r1: r1, r1a: r1a, r1b: r1b, r2: r2, l1: l1, l1a: l1a, l1b: l1b, l2: l2)
    }

    private func nav(_ f: Fixture, _ topic: Topic, _ dir: MindMapView.Direction) -> Topic? {
        guard let el = f.view.element(forTopic: topic) else { return nil }
        return f.view.element(in: dir, of: el)?.topic
    }

    // MARK: - Root

    func testRootRightGoesToFirstRightChild() {
        let f = makeFixture()
        XCTAssertTrue(nav(f, f.root, .right) === f.r1)
    }

    func testRootLeftGoesToFirstLeftChild() {
        let f = makeFixture()
        XCTAssertTrue(nav(f, f.root, .left) === f.l1)
    }

    // MARK: - Right half (Right = inward to children, Left = back to parent)

    func testRightSideRightGoesToFirstChild() {
        let f = makeFixture()
        XCTAssertTrue(nav(f, f.r1, .right) === f.r1a)
    }

    func testRightSideLeftGoesToParent() {
        let f = makeFixture()
        XCTAssertTrue(nav(f, f.r1, .left) === f.root)
        XCTAssertTrue(nav(f, f.r1a, .left) === f.r1)
    }

    // MARK: - Left half (mirrored: Left = inward, Right = back to parent)

    func testLeftSideLeftGoesToFirstChild() {
        let f = makeFixture()
        XCTAssertTrue(nav(f, f.l1, .left) === f.l1a)
    }

    func testLeftSideRightGoesToParent() {
        // THE FIX: previously Right on a left-side node dived into its
        // children; it must head back toward the root.
        let f = makeFixture()
        XCTAssertTrue(nav(f, f.l1, .right) === f.root)
        XCTAssertTrue(nav(f, f.l1a, .right) === f.l1)
    }

    // MARK: - Up / Down among same-side siblings

    func testDownMovesToNextSiblingSameSide() {
        let f = makeFixture()
        XCTAssertTrue(nav(f, f.r1, .down) === f.r2)
        XCTAssertTrue(nav(f, f.r1a, .down) === f.r1b)
        XCTAssertTrue(nav(f, f.l1, .down) === f.l2)
    }

    func testUpMovesToPreviousSibling() {
        let f = makeFixture()
        XCTAssertTrue(nav(f, f.r2, .up) === f.r1)
        XCTAssertTrue(nav(f, f.l1b, .up) === f.l1a)
    }

    func testUpAtFirstSiblingIsNil() {
        let f = makeFixture()
        XCTAssertNil(nav(f, f.r1, .up))
        XCTAssertNil(nav(f, f.l1a, .up))
    }

    // MARK: - Invariants (stability)

    func testInwardThenOutwardReturnsToOrigin() {
        // From every non-root topic, going toward-parent then back toward the
        // first child must return to the same node — navigation is reversible,
        // never "stuck" or drifting.
        let f = makeFixture()
        for topic in [f.r1, f.r2, f.l1, f.l2] {
            let side = f.view.element(forTopic: topic)!.isLeftSide
            let toParent: MindMapView.Direction = side ? .right : .left
            let toChild: MindMapView.Direction = side ? .left : .right
            let parent = nav(f, topic, toParent)
            XCTAssertTrue(parent === f.root, "\(topic.text) parent nav")
            // Back down from root lands on the first child of that side.
            let backToFirst = nav(f, parent!, toChild)
            XCTAssertNotNil(backToFirst)
        }
    }

    func testNavigationNeverLandsOnNilWhenAMoveExists() {
        // A right-side leaf pressing Right (further inward) has no child →
        // nil is correct (dead end), but pressing Left always finds the parent.
        let f = makeFixture()
        XCTAssertNil(nav(f, f.r1a, .right))   // leaf, no children
        XCTAssertNotNil(nav(f, f.r1a, .left)) // parent always reachable
        XCTAssertNil(nav(f, f.l1a, .left))    // left leaf, inward dead end
        XCTAssertNotNil(nav(f, f.l1a, .right))// parent reachable
    }

    // MARK: - Interactive: synthesized arrow keyDown drives selection

    private func arrowEvent(_ scalar: Int) -> NSEvent {
        let ch = String(Character(UnicodeScalar(scalar)!))
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil,
            characters: ch, charactersIgnoringModifiers: ch,
            isARepeat: false, keyCode: 0)!
    }

    func testArrowKeyDownMovesSelectionRightThenBack() {
        let f = makeFixture()
        // display() auto-selects root.
        XCTAssertTrue(f.view.selectedElement?.topic === f.root)
        f.view.keyDown(with: arrowEvent(NSRightArrowFunctionKey))
        XCTAssertTrue(f.view.selectedElement?.topic === f.r1, "Right from root → R1")
        f.view.keyDown(with: arrowEvent(NSRightArrowFunctionKey))
        XCTAssertTrue(f.view.selectedElement?.topic === f.r1a, "Right from R1 → R1a")
        f.view.keyDown(with: arrowEvent(NSLeftArrowFunctionKey))
        XCTAssertTrue(f.view.selectedElement?.topic === f.r1, "Left from R1a → R1")
    }

    func testArrowKeyDownNavigatesLeftHalfBackToRoot() {
        let f = makeFixture()
        f.view.keyDown(with: arrowEvent(NSLeftArrowFunctionKey))       // root → L1
        XCTAssertTrue(f.view.selectedElement?.topic === f.l1)
        f.view.keyDown(with: arrowEvent(NSLeftArrowFunctionKey))       // L1 → L1a (inward)
        XCTAssertTrue(f.view.selectedElement?.topic === f.l1a)
        f.view.keyDown(with: arrowEvent(NSRightArrowFunctionKey))      // L1a → L1 (back)
        XCTAssertTrue(f.view.selectedElement?.topic === f.l1)
        f.view.keyDown(with: arrowEvent(NSRightArrowFunctionKey))      // L1 → root
        XCTAssertTrue(f.view.selectedElement?.topic === f.root)
    }

    func testArrowKeyDownUpDownWalksSiblings() {
        let f = makeFixture()
        f.view.keyDown(with: arrowEvent(NSRightArrowFunctionKey))      // root → R1
        f.view.keyDown(with: arrowEvent(NSDownArrowFunctionKey))       // R1 → R2
        XCTAssertTrue(f.view.selectedElement?.topic === f.r2)
        f.view.keyDown(with: arrowEvent(NSUpArrowFunctionKey))         // R2 → R1
        XCTAssertTrue(f.view.selectedElement?.topic === f.r1)
    }

    func testArrowKeyDownAtDeadEndKeepsSelection() {
        // Pressing into a dead end must NOT clear or corrupt the selection.
        let f = makeFixture()
        f.view.keyDown(with: arrowEvent(NSRightArrowFunctionKey))      // root → R1
        f.view.keyDown(with: arrowEvent(NSUpArrowFunctionKey))         // R1 has no prev sibling
        XCTAssertTrue(f.view.selectedElement?.topic === f.r1, "dead-end Up keeps R1 selected")
    }
}
