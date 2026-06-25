import AppKit

/// A small fixed overview of the whole mind map, floated in the corner of the
/// scroll view in place of the (useless) scrollbars. Renders every topic as a
/// scaled block plus a rectangle for the current viewport; clicking or dragging
/// inside it recenters the canvas there. Hides itself when the whole map already
/// fits the viewport (nothing to navigate).
final class MinimapView: NSView {

    weak var scrollView: NSScrollView?
    weak var mapView: MindMapView?

    /// Document-coordinate origin (top-left) like the canvas, so projected
    /// topic frames need no axis inversion.
    override var isFlipped: Bool { true }

    static let preferredSize = CGSize(width: 168, height: 120)
    private let inset: CGFloat = 6

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.preferredSize))
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Point the minimap at a scroll view + its document canvas and start
    /// tracking scroll/resize so it redraws as the viewport moves.
    func attach(to scroll: NSScrollView, mapView map: MindMapView) {
        scrollView = scroll
        mapView = map
        let clip = scroll.contentView
        clip.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: NSView.boundsDidChangeNotification, object: clip)
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        refresh()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Redraw. Cheap; called on every scroll tick. The minimap is always
    /// visible while a non-empty map is loaded — it's a persistent overview,
    /// not just a when-you-can't-see-everything affordance. Only an empty
    /// canvas (no content) hides it.
    @objc func refresh() {
        guard let map = mapView, map.contentBounds.width > 0 else { isHidden = true; return }
        isHidden = false
        needsDisplay = true
    }

    // MARK: - Geometry

    /// World = the content extent unioned with the current viewport, so both
    /// the whole map and the visible window are always inside the minimap.
    private func transform() -> (MinimapTransform, viewport: CGRect)? {
        guard let map = mapView, let scroll = scrollView, map.contentBounds.width > 0 else { return nil }
        let viewport = scroll.documentVisibleRect
        let world = map.contentBounds.union(viewport)
        return (MinimapTransform(world: world, area: bounds.size, padding: inset), viewport)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.borderColor = NSColor.separatorColor.cgColor
        (isDark ? NSColor.black.withAlphaComponent(0.45)
                : NSColor.white.withAlphaComponent(0.7)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()

        guard let (t, viewport) = transform(), let root = mapView?.rootElement else { return }

        // Topic blocks. Root gets the accent tint; the rest a muted fill.
        let muted = NSColor.secondaryLabelColor.withAlphaComponent(0.55)
        root.traverse { el in
            let r = t.project(el.frame)
            // Sub-pixel topics still deserve a visible dot.
            let drawRect = r.width < 1.5 || r.height < 1.5
                ? CGRect(x: r.midX - 0.75, y: r.midY - 0.75, width: 1.5, height: 1.5) : r
            (el.level == 0 ? NSColor.controlAccentColor : muted).setFill()
            NSBezierPath(roundedRect: drawRect, xRadius: 1, yRadius: 1).fill()
        }

        // Viewport rectangle.
        let vp = t.project(viewport).intersection(bounds.insetBy(dx: 1, dy: 1))
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: vp).fill()
        NSColor.controlAccentColor.setStroke()
        let outline = NSBezierPath(rect: vp)
        outline.lineWidth = 1.5
        outline.stroke()
    }

    // MARK: - Click / drag to navigate

    override func mouseDown(with event: NSEvent) { recenter(with: event) }
    override func mouseDragged(with event: NSEvent) { recenter(with: event) }

    private func recenter(with event: NSEvent) {
        guard let (t, _) = transform(), let scroll = scrollView, let map = mapView else { return }
        let p = convert(event.locationInWindow, from: nil)
        let docPoint = t.unproject(p)
        let origin = MinimapGeometry.centeredOrigin(
            on: docPoint,
            viewportSize: scroll.documentVisibleRect.size,
            scrollable: map.bounds.size)
        let clip = scroll.contentView
        clip.scroll(to: origin)
        scroll.reflectScrolledClipView(clip)
        refresh()
    }
}
