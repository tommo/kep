import AppKit
import MindoModel
@testable import MindoMindMap

/// Build a headless MindMapView with an injected UndoManager so undo/redo
/// behavior can be driven without standing up an actual NSWindow. Setting
/// groupsByEvent=false stops NSUndoManager from coalescing every test
/// registration into a single runloop group — tests need to undo one op
/// at a time.
@MainActor
func makeHeadlessMindMap(
    map: MindMap,
    frame: NSRect = NSRect(x: 0, y: 0, width: 400, height: 300)
) -> (MindMapView, UndoManager) {
    let view = MindMapView(frame: frame)
    let mgr = UndoManager()
    mgr.groupsByEvent = false
    view.injectedUndoManager = mgr
    view.display(map: map)
    return (view, mgr)
}
