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
    /// Substring to highlight on every topic whose text contains it
    /// (case-insensitive). Drives the post-Find-in-Files visual marker.
    public var searchHighlight: String?
    /// Fires with the selected topic's outline index-path whenever the canvas
    /// selection changes — lets the outline panel highlight the matching row.
    public var onSelectionPath: ((String?) -> Void)?
    /// Per-document view-state persistence (zoom / pan / selection): restored on
    /// first reveal, saved when the canvas leaves its window.
    public var loadViewState: (() -> CanvasViewState?)?
    public var saveViewState: ((CanvasViewState) -> Void)?

    public init(
        map: MindMap,
        theme: MindMapTheme = .light,
        onChange: @escaping (MindMap) -> Void = { _ in },
        onExtraFileTap: ((URL) -> Void)? = nil,
        navigationTarget: String? = nil,
        searchHighlight: String? = nil,
        onSelectionPath: ((String?) -> Void)? = nil,
        loadViewState: (() -> CanvasViewState?)? = nil,
        saveViewState: ((CanvasViewState) -> Void)? = nil
    ) {
        self.map = map
        self.theme = theme
        self.onChange = onChange
        self.onExtraFileTap = onExtraFileTap
        self.navigationTarget = navigationTarget
        self.searchHighlight = searchHighlight
        self.onSelectionPath = onSelectionPath
        self.loadViewState = loadViewState
        self.saveViewState = saveViewState
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let scroll = NSScrollView()
        // Free-canvas clip view: panning runs a screenful past the content
        // instead of clamping to the document, so the canvas feels grabbed and
        // moved rather than scrolled like a page.
        scroll.contentView = CanvasClipView()
        // Scrollbars are near-useless on an infinite-feeling canvas — a corner
        // minimap (added below) replaces them for overview + navigation.
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        // No rubber-band bounce — panning (scrollWheel below drives the clip
        // directly) should feel like grabbing the canvas, not a scroll view.
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.25
        scroll.maxMagnification = 3.0
        scroll.borderType = .noBorder

        let view = MindMapView(frame: .zero)
        view.theme = theme
        view.onChange = { newMap in
            onChange(newMap)
            // Bubble change → update footer's topic count.
            context.coordinator.refreshFooter()
        }
        view.onExtraFileTap = onExtraFileTap
        let reportSelection = onSelectionPath
        view.onSelectionChange = { [weak coordinator = context.coordinator, weak view] in
            coordinator?.refreshFooter()
            // Defer to break out of any in-progress SwiftUI update (selection
            // can change during display()/updateNSView).
            let path = view?.selectedOutlinePath
            DispatchQueue.main.async { reportSelection?(path) }
        }
        view.loadViewState = loadViewState
        view.saveViewState = saveViewState
        view.display(map: map)
        scroll.documentView = view

        // Status footer below the scroll view — topic count + zoom percent.
        let footer = NSTextField(labelWithString: "")
        footer.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        footer.textColor = .secondaryLabelColor
        footer.alignment = .right
        footer.translatesAutoresizingMaskIntoConstraints = false

        scroll.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scroll)
        container.addSubview(footer)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
            footer.heightAnchor.constraint(equalToConstant: 16),
        ])

        // Corner minimap overlay (replaces the scrollbars). A constrained
        // sibling pinned to the bottom-right — on top of the scroll view, so
        // it stays put while the canvas scrolls underneath. Auto Layout keeps
        // it correctly placed regardless of when the scroll view gets sized
        // (the earlier floating-subview approach landed off-screen).
        let minimap = MinimapView()
        minimap.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(minimap)   // added last → renders above the scroll view
        NSLayoutConstraint.activate([
            minimap.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -10),
            minimap.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -10),
            minimap.widthAnchor.constraint(equalToConstant: MinimapView.preferredSize.width),
            minimap.heightAnchor.constraint(equalToConstant: MinimapView.preferredSize.height),
        ])
        minimap.attach(to: scroll, mapView: view)

        // Track magnification changes so the footer's zoom-percent stays
        // current. NSScrollView.willStartLiveMagnify isn't enough — we want
        // the value after every change, not just at gesture start.
        NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification,
            object: scroll,
            queue: .main
        ) { _ in context.coordinator.refreshFooter() }

        context.coordinator.view = view
        context.coordinator.scroll = scroll
        context.coordinator.footer = footer
        context.coordinator.minimap = minimap
        context.coordinator.refreshFooter()
        return container
    }

    /// Bounce the active zoom action up to the underlying view. Used by App
    /// menu items (Reset / Zoom In / Zoom Out).
    public static func zoom(_ scroll: NSScrollView, by factor: CGFloat) {
        guard let view = scroll.documentView as? MindMapView else { return }
        view.zoom(by: factor)
    }

    public static func resetZoom(_ scroll: NSScrollView) {
        guard let view = scroll.documentView as? MindMapView else { return }
        view.resetZoom()
    }

    public static func fitToViewport(_ scroll: NSScrollView) {
        guard let view = scroll.documentView as? MindMapView else { return }
        view.zoomToFit()
    }

    public func updateNSView(_ container: NSView, context: Context) {
        guard let view = context.coordinator.view else { return }
        view.theme = theme
        view.onExtraFileTap = onExtraFileTap
        view.loadViewState = loadViewState
        view.saveViewState = saveViewState
        if view.searchHighlight != searchHighlight {
            view.searchHighlight = searchHighlight
            view.needsDisplay = true
        }
        if view.mindMap !== map {
            view.display(map: map)
            context.coordinator.refreshFooter()
        }
        // If the target changed since last update, run navigation now.
        if let target = navigationTarget, target != context.coordinator.lastNavigated {
            context.coordinator.lastNavigated = target
            DispatchQueue.main.async { view.navigate(to: target) }
        }
        // Re-grab focus when the canvas is the active document — fixes the
        // "keyboard nav doesn't work until I click a topic" issue when the
        // sidebar List initially holds first responder.
        DispatchQueue.main.async { view.grabFocus() }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator {
        weak var view: MindMapView?
        weak var scroll: NSScrollView?
        weak var footer: NSTextField?
        weak var minimap: MinimapView?
        var lastNavigated: String?

        /// Recompute the canvas footer text — topic count, optional
        /// selection count, zoom percent. Called after document load,
        /// mutations, selection changes, and zoom changes.
        func refreshFooter() {
            guard let footer = footer else { return }
            let topicCount = view?.rootElement?.topic.subtreeCount() ?? 0
            let zoomPct = Int(round((scroll?.magnification ?? 1) * 100))
            let selCount = view?.selectedTopics.count ?? 0
            // Only mention selection when ≥2 — single-select is implied by
            // the rendered selection ring and would just clutter the bar.
            if selCount >= 2 {
                footer.stringValue = "\(topicCount) topics · \(selCount) selected · \(zoomPct)%"
            } else {
                footer.stringValue = "\(topicCount) topics · \(zoomPct)%"
            }
            // Content/zoom may have shifted — keep the overview current.
            minimap?.refresh()
        }
    }
}
