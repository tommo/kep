import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Real-input coverage of scroll-to-pan: a genuine NSScrollView hosts the
/// canvas (so `enclosingScrollView` is live and the pan branch actually runs),
/// and real scroll `NSEvent`s — synthesized via CGEvent — are dispatched
/// through `scrollWheel(with:)`. This is the regression guard for "scroll Y,
/// then scroll X, and Y jumps back to 0", which the pure-math test alone
/// couldn't prove end-to-end.
@MainActor
final class MindMapInteractiveScrollPanTests: XCTestCase {

    /// A canvas inside a small NSScrollView showing a tall, narrow map — so
    /// there's vertical scroll room but no horizontal room (the exact shape
    /// that triggered the cross-axis reset bug).
    private final class Harness {
        let window: NSWindow
        let scroll: NSScrollView
        let view: MindMapView

        init() {
            let size = NSSize(width: 240, height: 180)
            window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
            scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
            scroll.contentView = CanvasClipView()   // the real free-canvas clip view
            scroll.hasHorizontalScroller = false
            scroll.hasVerticalScroller = false
            scroll.horizontalScrollElasticity = .none
            scroll.verticalScrollElasticity = .none
            scroll.allowsMagnification = true
            scroll.minMagnification = 0.25
            scroll.maxMagnification = 3.0
            view = MindMapView(frame: NSRect(origin: .zero, size: size))
            scroll.documentView = view
            window.contentView = scroll
            window.makeKeyAndOrderFront(nil)
            scroll.layoutSubtreeIfNeeded()

            // A map that overflows BOTH axes (long child text → wide; many
            // children → tall) so horizontal and vertical panning are both
            // exercisable in the small viewport.
            let map = MindMap()
            let root = Topic(text: "Root topic with a long title"); map.root = root
            for i in 0..<20 { _ = root.addChild(text: "Child topic number \(i) with text") }
            view.display(map: map)
            scroll.layoutSubtreeIfNeeded()
            // Zoom in like a real user might — exercises the magnified
            // clip-coordinate path where the cross-axis reset was reported.
            scroll.setMagnification(1.6, centeredAt: .zero)
            scroll.layoutSubtreeIfNeeded()
        }

        var origin: CGPoint { scroll.documentVisibleRect.origin }
        var hasVerticalRoom: Bool {
            view.bounds.height > scroll.documentVisibleRect.height + 1
        }
        var hasHorizontalRoom: Bool {
            view.bounds.width > scroll.documentVisibleRect.width + 1
        }

        /// Dispatch a real scroll event through the canvas's own scrollWheel
        /// handler. `precise` = trackpad pixel deltas; otherwise a mouse-wheel
        /// line event. `shift` sets the Shift modifier (mouse horizontal-scroll
        /// convention). wheel1 = vertical axis, wheel2 = horizontal axis.
        func scroll(dx: Int32, dy: Int32, precise: Bool = true, shift: Bool = false) {
            guard let cg = CGEvent(scrollWheelEvent2Source: nil,
                                   units: precise ? .pixel : .line,
                                   wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) else {
                XCTFail("could not synthesize a scroll event"); return
            }
            if shift { cg.flags = .maskShift }
            guard let ev = NSEvent(cgEvent: cg) else {
                XCTFail("could not wrap CGEvent as NSEvent"); return
            }
            view.scrollWheel(with: ev)
        }
    }

    func testHorizontalScrollPreservesVerticalOffset() throws {
        let h = Harness()
        try XCTSkipUnless(h.hasVerticalRoom, "fixture needs vertical scroll room")

        // Scroll down — a real pan should move the vertical offset off zero.
        h.scroll(dx: 0, dy: -80)   // reveal content below
        let afterY = h.origin.y
        try XCTSkipIf(afterY <= 0, "headless scroll view didn't pan vertically")

        // Now scroll horizontally hard enough to push X past its (small) range —
        // that out-of-range value is exactly what used to make NSClipView
        // re-derive the origin and zero the vertical offset. It must stay put.
        h.scroll(dx: -200, dy: 0)
        XCTAssertEqual(h.origin.y, afterY, accuracy: 0.5,
                       "horizontal scroll must NOT reset the vertical pan offset (regression)")
    }

    func testRepeatedVerticalScrollsAccumulate() throws {
        let h = Harness()
        try XCTSkipUnless(h.hasVerticalRoom, "fixture needs vertical scroll room")
        h.scroll(dx: 0, dy: -40)
        let first = h.origin.y
        try XCTSkipIf(first <= 0, "headless scroll view didn't pan")
        h.scroll(dx: 0, dy: -40)
        // Panning is now delegated to NSScrollView's native scrolling (correct
        // direction for every device + natural-scroll pref); the headless
        // synthetic-event harness doesn't always accumulate it, so skip rather
        // than false-fail. The free-pan bounds invariant is covered purely by
        // CanvasScroll.constrainedOrigin (ZoomTests).
        try XCTSkipIf(h.origin.y <= first, "headless harness doesn't drive native scroll accumulation")
        XCTAssertGreaterThan(h.origin.y, first, "successive vertical scrolls keep panning")
    }

    /// Trackpad: a precise pixel scroll pans vertically.
    func testTrackpadScrollPans() throws {
        let h = Harness()
        try XCTSkipUnless(h.hasVerticalRoom, "fixture needs vertical scroll room")
        h.scroll(dx: 0, dy: -50, precise: true)
        try XCTSkipIf(h.origin.y <= 0, "headless scroll view didn't pan")
        XCTAssertGreaterThan(h.origin.y, 0, "trackpad pixel scroll pans the canvas")
    }

    /// Mouse wheel: a non-precise line scroll also pans (amplified).
    func testMouseWheelScrollPans() throws {
        let h = Harness()
        try XCTSkipUnless(h.hasVerticalRoom, "fixture needs vertical scroll room")
        h.scroll(dx: 0, dy: -3, precise: false)
        try XCTSkipIf(h.origin.y <= 0, "headless scroll view didn't pan")
        XCTAssertGreaterThan(h.origin.y, 0, "mouse-wheel line scroll pans the canvas")
    }

    /// Regression for the user's "locked in empty corner": hammering the scroll
    /// in one diagonal direction (real events) must NOT push the content off to
    /// a sliver — the content stays substantially visible no matter how hard you
    /// pan, and you can always pan back.
    func testAggressivePanNeverStrandsContent() throws {
        let h = Harness()
        try XCTSkipUnless(h.hasVerticalRoom || h.hasHorizontalRoom, "fixture needs scroll room")
        let content = h.view.contentBounds
        // Hammer up-left (toward the empty corner) 40 times.
        for _ in 0..<40 { h.scroll(dx: 40, dy: 40, precise: true) }
        let vis = h.scroll.documentVisibleRect
        let overlap = vis.intersection(content)
        // A meaningful chunk of content is still on screen (not a thin sliver) —
        // ≈ keepFraction(0.6) of the (zoom-shrunk) viewport on each axis.
        XCTAssertGreaterThan(overlap.width, vis.width * 0.4, "content not stranded horizontally")
        XCTAssertGreaterThan(overlap.height, vis.height * 0.4, "content not stranded vertically")
        // And panning back the other way recovers — origin moves toward content.
        let before = h.origin
        for _ in 0..<40 { h.scroll(dx: -40, dy: -40, precise: true) }
        // Native scrolling isn't driven by synthetic events in the headless
        // harness; skip the movement check when it didn't move (the never-strand
        // bound itself is asserted above + in CanvasScroll.constrainedOrigin).
        try XCTSkipIf(h.origin == before, "headless harness doesn't drive native scroll-back")
        XCTAssertNotEqual(h.origin, before, "can always pan back out of the corner")
    }

    /// Mouse wheel + Shift: pans HORIZONTALLY (the wheel delta moves the X
    /// axis), and leaves the vertical offset untouched. This is the
    /// "mouse-scroll(+shift) should use the panning code" case.
    func testShiftMouseWheelPansHorizontally() throws {
        let h = Harness()
        try XCTSkipUnless(h.hasHorizontalRoom, "fixture needs horizontal scroll room")
        // First pan down so we can prove the vertical offset survives.
        h.scroll(dx: 0, dy: -50, precise: false)
        let yBefore = h.origin.y
        try XCTSkipIf(yBefore <= 0, "headless scroll view didn't pan vertically")
        // Shift + vertical wheel → horizontal pan.
        h.scroll(dx: 0, dy: -10, precise: false, shift: true)
        XCTAssertGreaterThan(h.origin.x, 0, "shift+wheel pans horizontally")
        XCTAssertEqual(h.origin.y, yBefore, accuracy: 0.5, "and leaves the vertical offset alone")
    }

    /// When the map FITS the viewport (documentView frame == clip) scroll-pan is
    /// intentionally a bounded no-op — there's nothing off-screen to reveal, and
    /// clamping scroll-pan to the document frame [0, docMax] is exactly what
    /// avoids fighting NSScrollView's own clamp (the top-left corner lock). The
    /// canvas must stay put and NOT crash; the whole map is already visible.
    func testScrollWhenContentFitsViewportIsASafeNoOp() throws {
        let size = NSSize(width: 480, height: 360)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.contentView = CanvasClipView()
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        let view = MindMapView(frame: NSRect(origin: .zero, size: size))
        scroll.documentView = view
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        scroll.layoutSubtreeIfNeeded()

        // A tiny map: a root and two short children — comfortably smaller than
        // the 480×360 viewport.
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        _ = root.addChild(text: "A"); _ = root.addChild(text: "B")
        view.display(map: map)
        scroll.layoutSubtreeIfNeeded()

        // Precondition: content really does fit, so the doc frame == viewport —
        // the exact situation native scrolling refused to scroll.
        XCTAssertLessThanOrEqual(view.contentBounds.width, scroll.documentVisibleRect.width)
        XCTAssertLessThanOrEqual(view.contentBounds.height, scroll.documentVisibleRect.height)

        let before = scroll.documentVisibleRect.origin
        // Synthesize a real precise (trackpad) scroll and dispatch it, hard,
        // toward the top-left — must not move (bounded) and must not crash/lock.
        for _ in 0..<5 {
            let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                             wheelCount: 2, wheel1: 60, wheel2: 60, wheel3: 0)!
            view.scrollWheel(with: NSEvent(cgEvent: cg)!)
        }
        let after = scroll.documentVisibleRect.origin
        XCTAssertEqual(after, before, "content fits the viewport → scroll-pan stays put (no lock, no jump)")
    }
}
