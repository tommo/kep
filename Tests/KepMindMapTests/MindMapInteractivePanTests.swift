import XCTest
import AppKit
import KepModel
@testable import KepMindMap

/// Mouse panning: a plain drag on empty canvas must scroll the map (the hand
/// tool), and Shift+drag must still marquee-select. Driven through a real
/// NSScrollView + window with events posted at fixed WINDOW locations — which
/// is how a real hand-drag works: the cursor stays put on screen while the
/// content scrolls underneath it.
@MainActor
final class MindMapInteractivePanTests: XCTestCase {

    /// A deep right-going chain → very WIDE, one row TALL, so there is plenty
    /// of horizontal scroll room and the window's bottom band is empty canvas.
    private func makeHarness() -> (NSWindow, NSScrollView, MindMapView, Topic) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        var cur = root
        for i in 0..<14 {
            let c = cur.addChild(text: "Node \(i)")
            c.setAttribute(TopicAttribute.leftSide, "false")
            cur = c
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true
        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        scroll.documentView = view
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        view.display(map: map)
        return (window, scroll, view, root)
    }

    private func post(_ window: NSWindow, _ type: NSEvent.EventType, _ p: CGPoint,
                      _ mods: NSEvent.ModifierFlags = []) {
        let ev = NSEvent.mouseEvent(
            with: type, location: p, modifierFlags: mods, timestamp: 0,
            windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
        window.sendEvent(ev)
    }

    /// Drag in WINDOW coordinates (y-up), along the empty bottom band.
    private func dragWindow(_ window: NSWindow, from: CGPoint, to: CGPoint,
                            steps: Int = 8, mods: NSEvent.ModifierFlags = []) {
        post(window, .leftMouseDown, from, mods)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            post(window, .leftMouseDragged,
                 CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), mods)
        }
        post(window, .leftMouseUp, to, mods)
    }

    func testPlainDragOnEmptyCanvasPans() throws {
        let (window, scroll, view, _) = makeHarness()
        // Need real horizontal scroll room for the pan to register.
        let docWidth = view.frame.width
        try XCTSkipIf(docWidth <= scroll.contentView.bounds.width + 10,
                      "content not wider than viewport — nothing to pan")
        // Start from the middle so there's room to scroll either way.
        scroll.contentView.scroll(to: NSPoint(x: (docWidth - scroll.contentView.bounds.width) / 2, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        let before = scroll.contentView.bounds.origin

        // Drag leftward along the empty bottom band (window y-up = 24).
        dragWindow(window, from: CGPoint(x: 360, y: 24), to: CGPoint(x: 140, y: 24))

        let after = scroll.contentView.bounds.origin
        XCTAssertNotEqual(after.x, before.x, accuracy: 0, "a plain empty-canvas drag scrolled the canvas")
        XCTAssertGreaterThan(abs(after.x - before.x), 20, "the pan moved a meaningful distance")
    }

    func testPlainClickOnEmptyCanvasStillDeselects() throws {
        let (window, _, view, root) = makeHarness()
        view.selectElement(view.element(forTopic: root))
        XCTAssertNotNil(view.selectedElement)
        // A press that doesn't move (empty bottom band) is a click → deselect.
        post(window, .leftMouseDown, CGPoint(x: 200, y: 24))
        post(window, .leftMouseUp, CGPoint(x: 200, y: 24))
        XCTAssertNil(view.selectedElement, "click on empty canvas clears selection (no pan happened)")
    }

    /// Shift+drag must NOT pan — it starts a marquee instead (marquee selection
    /// itself is covered by MindMapInteractiveDragEditTests). This pins down the
    /// pan-vs-marquee disambiguation on the gesture that shares the empty canvas.
    func testShiftDragDoesNotPan() throws {
        let (window, scroll, view, _) = makeHarness()
        let docWidth = view.frame.width
        scroll.contentView.scroll(to: NSPoint(x: (docWidth - scroll.contentView.bounds.width) / 2, y: 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        let before = scroll.contentView.bounds.origin
        view.selectElement(nil)
        dragWindow(window, from: CGPoint(x: 360, y: 24), to: CGPoint(x: 140, y: 24), mods: .shift)
        XCTAssertEqual(scroll.contentView.bounds.origin.x, before.x, accuracy: 0.5,
                       "Shift+drag starts a marquee, it must not pan the canvas")
    }
}
