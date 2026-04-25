import SwiftUI
import AppKit
import MindoModel

/// SwiftUI bridge for `MindMapView`. Wraps the AppKit canvas in a scroll view
/// so SwiftUI tabs / windows can host it.
public struct MindMapCanvas: NSViewRepresentable {
    public var map: MindMap
    public var theme: MindMapTheme
    public var onChange: (MindMap) -> Void
    public var onExtraFileTap: ((URL) -> Void)?

    public init(
        map: MindMap,
        theme: MindMapTheme = .light,
        onChange: @escaping (MindMap) -> Void = { _ in },
        onExtraFileTap: ((URL) -> Void)? = nil
    ) {
        self.map = map
        self.theme = theme
        self.onChange = onChange
        self.onExtraFileTap = onExtraFileTap
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 3.0
        scroll.borderType = .noBorder

        let view = MindMapView(frame: .zero)
        view.theme = theme
        view.onChange = onChange
        view.onExtraFileTap = onExtraFileTap
        view.display(map: map)
        scroll.documentView = view
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? MindMapView else { return }
        view.theme = theme
        view.onExtraFileTap = onExtraFileTap
        if view.mindMap !== map {
            view.display(map: map)
        }
    }
}
