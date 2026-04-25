import AppKit
import MindoModel
@testable import MindoMindMap

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
