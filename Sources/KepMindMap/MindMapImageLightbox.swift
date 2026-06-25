import AppKit

/// Borderless modal-ish window that shows a topic's embedded image at
/// full resolution. ESC dismisses; click outside the image area also
/// dismisses. Mirrors mindolph's ImagePreviewDialog.
public enum MindMapImageLightbox {

    public static func present(image: NSImage, near sourceWindow: NSWindow?) {
        let host = LightboxWindowController(image: image)
        host.showWindow(nil)
        if let sourceWindow {
            host.window?.center()
            // Anchor near the source so the lightbox doesn't surprise the
            // user by jumping to the primary screen.
            var frame = host.window?.frame ?? .zero
            frame.origin.x = max(0, sourceWindow.frame.midX - frame.width / 2)
            frame.origin.y = max(0, sourceWindow.frame.midY - frame.height / 2)
            host.window?.setFrame(frame, display: true)
        }
        host.window?.makeKeyAndOrderFront(nil)
        // Retain via a static cache until close — NSWindowController doesn't
        // self-retain after showWindow.
        Self.live.append(host)
        host.onClose = { [weak host] in
            Self.live.removeAll { $0 === host }
        }
    }

    private static var live: [LightboxWindowController] = []
}

private final class LightboxWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(image: NSImage) {
        // Cap to ~80% of main screen so massive thumbnails stay on-screen.
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1400, height: 900)
        let cap = CGSize(width: screen.width * 0.8, height: screen.height * 0.8)
        let raw = image.size
        let scale = min(1.0, min(cap.width / raw.width, cap.height / raw.height))
        let drawSize = CGSize(width: raw.width * scale, height: raw.height * scale)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: drawSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Image"
        panel.isFloatingPanel = false
        panel.isReleasedWhenClosed = false
        panel.level = .normal

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = NSRect(origin: .zero, size: drawSize)
        imageView.autoresizingMask = [.width, .height]
        panel.contentView = imageView

        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not implemented") }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { close() } else { super.keyDown(with: event) } // 53 = Esc
    }
}
