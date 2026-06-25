import SwiftUI
import AppKit

/// Controls zoom for a `ZoomableImageView` from SwiftUI (Fit / 100% buttons,
/// live zoom readout). The view wires its scroll view in on appear.
@MainActor
public final class ImageZoomController: ObservableObject {
    @Published public var zoom: CGFloat = 1
    fileprivate weak var scrollView: NSScrollView?

    public init() {}

    /// Zoom so the whole image fits the viewport (never upscales past 100%).
    public func fit() {
        guard let sv = scrollView, let doc = sv.documentView,
              doc.frame.width > 0, doc.frame.height > 0,
              sv.contentSize.width > 0, sv.contentSize.height > 0 else { return }
        let scale = min(sv.contentSize.width / doc.frame.width,
                        sv.contentSize.height / doc.frame.height)
        sv.magnification = max(min(scale, 1), sv.minMagnification)
        zoom = sv.magnification
    }

    public func actualSize() {
        scrollView?.magnification = 1
        zoom = 1
    }
}

/// A pannable, pinch-zoomable image viewer backed by NSScrollView magnification
/// (free scroll + trackpad pinch). Standalone image-file viewing (javamind
/// ScalableImageView parity).
public struct ZoomableImageView: NSViewRepresentable {
    public let image: NSImage
    @ObservedObject var controller: ImageZoomController

    public init(image: NSImage, controller: ImageZoomController) {
        self.image = image
        self.controller = controller
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.allowsMagnification = true
        scroll.minMagnification = 0.05
        scroll.maxMagnification = 16
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.backgroundColor = .underPageBackgroundColor

        let imageView = NSImageView()
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(origin: .zero, size: image.size)
        scroll.documentView = imageView

        controller.scrollView = scroll
        context.coordinator.controller = controller
        context.coordinator.scrollView = scroll
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.magnified),
            name: NSScrollView.didEndLiveMagnifyNotification, object: scroll)
        DispatchQueue.main.async { controller.fit() }
        return scroll
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let iv = nsView.documentView as? NSImageView, iv.image !== image else { return }
        iv.image = image
        iv.frame = NSRect(origin: .zero, size: image.size)
        DispatchQueue.main.async { controller.fit() }
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    public final class Coordinator: NSObject {
        weak var controller: ImageZoomController?
        weak var scrollView: NSScrollView?
        @objc func magnified() {
            // didEndLiveMagnify is delivered on the main thread.
            guard let sv = scrollView else { return }
            MainActor.assumeIsolated { controller?.zoom = sv.magnification }
        }
    }
}
