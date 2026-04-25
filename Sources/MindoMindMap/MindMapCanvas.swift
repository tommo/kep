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
    /// External nav target — when this changes, navigate the canvas.
    public var navigationTarget: String?

    public init(
        map: MindMap,
        theme: MindMapTheme = .light,
        onChange: @escaping (MindMap) -> Void = { _ in },
        onExtraFileTap: ((URL) -> Void)? = nil,
        navigationTarget: String? = nil
    ) {
        self.map = map
        self.theme = theme
        self.onChange = onChange
        self.onExtraFileTap = onExtraFileTap
        self.navigationTarget = navigationTarget
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
        context.coordinator.view = view
        return scroll
    }

    public func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? MindMapView else { return }
        view.theme = theme
        view.onExtraFileTap = onExtraFileTap
        if view.mindMap !== map {
            view.display(map: map)
        }
        // If the target changed since last update, run navigation now.
        if let target = navigationTarget, target != context.coordinator.lastNavigated {
            context.coordinator.lastNavigated = target
            DispatchQueue.main.async { view.navigate(to: target) }
        }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        weak var view: MindMapView?
        var lastNavigated: String?
    }
}
