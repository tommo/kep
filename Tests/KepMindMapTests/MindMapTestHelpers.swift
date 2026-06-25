import AppKit
import KepModel
@testable import KepMindMap

/// Build a headless MindMapView (no NSWindow) showing `map`. Use this
/// when the test only inspects layout / selection / hit-testing.
@MainActor
func makeHeadlessMindMap(
    map: MindMap,
    frame: NSRect = NSRect(x: 0, y: 0, width: 400, height: 300)
) -> MindMapView {
    let view = MindMapView(frame: frame)
    view.display(map: map)
    return view
}

/// A MindMapView inside a REAL key window, so the full responder chain and
/// NSTextField field editor are live. Drive it with `sendKey` to exercise
/// genuine NSEvent dispatch (performKeyEquivalent → keyDown, and typing into
/// the inline editor's field editor) — the things the window-less helper
/// cannot reach. Returns nil-capable via XCTSkip at the call site if the
/// environment can't host a key window.
@MainActor
final class WindowedMindMap {
    let window: NSWindow
    let view: MindMapView

    init(map: MindMap, size: NSSize = NSSize(width: 900, height: 640)) {
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false)
        view = MindMapView(frame: NSRect(origin: .zero, size: size))
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.display(map: map)
        window.makeFirstResponder(view)
    }

    /// Post a real key-down event through the window's event dispatch — it
    /// routes through performKeyEquivalent / keyDown, or into the inline
    /// editor's field editor when one is first responder.
    func sendKey(_ chars: String, _ mods: NSEvent.ModifierFlags = []) {
        let ev = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: mods,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: chars, charactersIgnoringModifiers: chars,
            isARepeat: false, keyCode: 0)!
        window.sendEvent(ev)
    }

    func sendArrow(_ functionKey: Int, _ mods: NSEvent.ModifierFlags = []) {
        sendKey(String(Character(UnicodeScalar(functionKey)!)), mods)
    }

    /// Drive a key EQUIVALENT (a ⌘/⌥-modified key) the way NSApplication
    /// does — through `performKeyEquivalent`, which is where the canvas
    /// handles ⌘+arrow topic moves. Returns whether it was handled.
    @discardableResult
    func sendKeyEquivalent(_ chars: String, _ mods: NSEvent.ModifierFlags) -> Bool {
        let ev = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: mods,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: chars, charactersIgnoringModifiers: chars,
            isARepeat: false, keyCode: 0)!
        return view.performKeyEquivalent(with: ev)
    }

    @discardableResult
    func sendArrowEquivalent(_ functionKey: Int, _ mods: NSEvent.ModifierFlags) -> Bool {
        sendKeyEquivalent(String(Character(UnicodeScalar(functionKey)!)), mods)
    }

    /// Post a real left mouse-down + up at a point given in the view's
    /// (flipped) coordinate space — routed through the window so hit-testing
    /// and the view's mouseDown/mouseUp run for real. `clickCount` 2 = a
    /// double-click (drives begin-inline-edit).
    func click(viewPoint p: CGPoint, clickCount: Int = 1, mods: NSEvent.ModifierFlags = []) {
        let inWindow = view.convert(p, to: nil)
        for phase in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let ev = NSEvent.mouseEvent(
                with: phase, location: inWindow, modifierFlags: mods,
                timestamp: 0, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: clickCount, pressure: 1)!
            window.sendEvent(ev)
        }
    }

    /// Click the centre of `topic`'s laid-out element.
    func click(topic: Topic, clickCount: Int = 1, mods: NSEvent.ModifierFlags = []) {
        guard let el = view.element(forTopic: topic) else { return }
        click(viewPoint: CGPoint(x: el.frame.midX, y: el.frame.midY), clickCount: clickCount, mods: mods)
    }

    private func mouse(_ type: NSEvent.EventType, _ viewPoint: CGPoint, _ mods: NSEvent.ModifierFlags = []) {
        let ev = NSEvent.mouseEvent(
            with: type, location: view.convert(viewPoint, to: nil), modifierFlags: mods,
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
        window.sendEvent(ev)
    }

    /// Drag from `from` to `to` (view coordinates) with intermediate steps, so
    /// the drag passes the start threshold and updates targets en route.
    func drag(from: CGPoint, to: CGPoint, steps: Int = 6, mods: NSEvent.ModifierFlags = []) {
        mouse(.leftMouseDown, from, mods)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t)
            mouse(.leftMouseDragged, p, mods)
        }
        mouse(.leftMouseUp, to, mods)
    }

    /// Drag one topic's centre onto another's.
    func drag(topic src: Topic, onto dst: Topic, mods: NSEvent.ModifierFlags = []) {
        guard let s = view.element(forTopic: src), let d = view.element(forTopic: dst) else { return }
        drag(from: CGPoint(x: s.frame.midX, y: s.frame.midY),
             to: CGPoint(x: d.frame.midX, y: d.frame.midY), mods: mods)
    }

    /// The live text in the inline editor's field editor (what the user would
    /// actually see), or nil when no editor is open.
    var editorText: String? {
        guard let field = view.inlineEditor else { return nil }
        return field.currentEditor()?.string ?? field.stringValue
    }
}

/// Same as `makeHeadlessMindMap` but with an injected UndoManager so undo
/// / redo can be driven directly. Setting groupsByEvent=false stops
/// NSUndoManager from coalescing every test registration into a single
/// runloop group — tests need to undo one op at a time.
@MainActor
func makeHeadlessMindMapWithUndo(
    map: MindMap,
    frame: NSRect = NSRect(x: 0, y: 0, width: 400, height: 300)
) -> (MindMapView, UndoManager) {
    let mgr = UndoManager()
    mgr.groupsByEvent = false
    let view = MindMapView(frame: frame)
    view.injectedUndoManager = mgr
    view.display(map: map)
    return (view, mgr)
}
