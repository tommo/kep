import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// Round-trips the per-document canvas view state (zoom / pan / selection)
/// through a real NSScrollView-hosted canvas, the way the persistence feature
/// captures on tab-switch and restores on reopen.
@MainActor
final class CanvasViewStateTests: XCTestCase {

    private func makeHosted() -> (NSWindow, NSScrollView, MindMapView, root: Topic, a: Topic, b: Topic) {
        let size = NSSize(width: 400, height: 300)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.contentView = CanvasClipView()
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 3.0
        let view = MindMapView(frame: NSRect(origin: .zero, size: size))
        scroll.documentView = view
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        scroll.layoutSubtreeIfNeeded()

        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        let a = root.addChild(text: "A")
        let b = root.addChild(text: "B")
        view.display(map: map)
        scroll.layoutSubtreeIfNeeded()
        return (window, scroll, view, root, a, b)
    }

    func testCaptureApplyRoundTrip() {
        let (_, scroll, view, _, a, _) = makeHosted()

        // Put the canvas in a known state: zoomed, panned, child A selected.
        scroll.magnification = 1.5
        scroll.contentView.scroll(to: CGPoint(x: 60, y: 45))
        scroll.reflectScrolledClipView(scroll.contentView)
        view.selectElement(view.element(forTopic: a))

        let saved = view.captureViewState()
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.zoom ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(saved?.selectedPath, "0", "A is child index 0")

        // Disturb everything.
        scroll.magnification = 1.0
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        view.selectElement(view.element(forTopic: view.rootElement!.topic))

        // Restore.
        view.applyViewState(saved!)
        let after = view.captureViewState()!

        XCTAssertEqual(after.zoom, saved!.zoom, accuracy: 0.001, "zoom restored")
        XCTAssertEqual(after.originX, saved!.originX, accuracy: 1, "pan X restored")
        XCTAssertEqual(after.originY, saved!.originY, accuracy: 1, "pan Y restored")
        XCTAssertEqual(after.selectedPath, "0", "selection restored")
    }

    /// End-to-end open path: a canvas with a host-provided saved view state
    /// must reveal already at that zoom + selection (the persisted-restore
    /// feature). Guards the open-reveal wiring; the no-visible-jump ordering
    /// itself is enforced by revealWhenLaidOut marking revealed before applying.
    func testOpenRevealsAtSavedState() {
        let size = NSSize(width: 400, height: 300)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.contentView = CanvasClipView()
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 3.0
        let view = MindMapView(frame: NSRect(origin: .zero, size: size))
        scroll.documentView = view
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        scroll.layoutSubtreeIfNeeded()

        let map = MindMap()
        let root = Topic(text: "Root"); map.root = root
        _ = root.addChild(text: "A")
        _ = root.addChild(text: "B")

        // Host provides a saved state to restore on reveal.
        let saved = CanvasViewState(zoom: 1.5, originX: 0, originY: 0, selectedPath: "0")
        view.loadViewState = { saved }
        view.display(map: map)

        // Let the async reveal (+ any reentrant magnification resize) settle.
        let exp = expectation(description: "reveal")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(view.alphaValue, 1, accuracy: 0.001, "canvas revealed")
        let after = view.captureViewState()!
        XCTAssertEqual(after.zoom, 1.5, accuracy: 0.01, "revealed at the saved zoom")
        XCTAssertEqual(after.selectedPath, "0", "revealed with the saved selection")
    }

    func testCaptureWithNoSelection() {
        let (_, _, view, _, _, _) = makeHosted()
        view.selectElement(nil)
        let s = view.captureViewState()
        XCTAssertNil(s?.selectedPath, "no selection → nil path")
    }

    func testCodableRoundTrip() throws {
        let s = CanvasViewState(zoom: 1.25, originX: 12.5, originY: -8, selectedPath: "0/2")
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(CanvasViewState.self, from: data)
        XCTAssertEqual(s, back)
    }
}
