import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// ⌘ + scroll-wheel zoom — the mouse (non-trackpad) zoom that pairs with
/// drag-to-pan so the canvas is fully navigable with a plain mouse. Covers the
/// pure per-tick factor and a real ⌘+scroll event synthesised via CGEvent.
@MainActor
final class MindMapInteractiveZoomTests: XCTestCase {

    // MARK: - Pure factor

    func testScrollZoomFactorDirectionAndClamp() {
        XCTAssertGreaterThan(MindMapView.scrollZoomFactor(delta: 5), 1, "scroll up zooms in")
        XCTAssertLessThan(MindMapView.scrollZoomFactor(delta: -5), 1, "scroll down zooms out")
        XCTAssertEqual(MindMapView.scrollZoomFactor(delta: 0), 1, "no delta = no zoom")
        // A huge wheel notch is capped to ±20% so one notch can't leap the range.
        XCTAssertEqual(MindMapView.scrollZoomFactor(delta: 9999), 1.2, accuracy: 0.0001)
        XCTAssertEqual(MindMapView.scrollZoomFactor(delta: -9999), 0.8, accuracy: 0.0001)
    }

    // MARK: - Real event

    private func makeScrollHarness() -> (NSScrollView, MindMapView) {
        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        for i in 0..<6 { root.addChild(text: "Child \(i)").setAttribute(TopicAttribute.leftSide, "false") }
        let scroll = CanvasScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        scroll.contentView = CanvasClipView()
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 3.0
        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        scroll.documentView = view
        view.display(map: map)
        return (scroll, view)
    }

    private func scrollEvent(deltaY: Int32, command: Bool) -> NSEvent? {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                               wheelCount: 1, wheel1: deltaY, wheel2: 0, wheel3: 0) else { return nil }
        if command { cg.flags = .maskCommand }
        return NSEvent(cgEvent: cg)
    }

    func testCommandScrollZoomsIn() throws {
        let (scroll, view) = makeScrollHarness()
        let before = scroll.magnification
        guard let ev = scrollEvent(deltaY: 30, command: true) else {
            throw XCTSkip("cannot synthesise a scroll-wheel CGEvent in this environment")
        }
        view.scrollWheel(with: ev)
        XCTAssertGreaterThan(scroll.magnification, before, "⌘+scroll up magnified the canvas")
    }

    func testBareScrollDoesNotZoom() throws {
        let (scroll, view) = makeScrollHarness()
        let before = scroll.magnification
        guard let ev = scrollEvent(deltaY: 30, command: false) else {
            throw XCTSkip("cannot synthesise a scroll-wheel CGEvent in this environment")
        }
        view.scrollWheel(with: ev)
        XCTAssertEqual(scroll.magnification, before, accuracy: 0.0001,
                       "a bare scroll pans, it must not zoom")
    }
}
