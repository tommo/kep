import AppKit
import MindoModel

extension MindMapView {

    /// Standard `paste(_:)` responder action — fires on ⌘V when the canvas
    /// is first responder. When the pasteboard has an image and a topic is
    /// selected, embed the image as base64 PNG in `mmd.image`. NSView
    /// itself doesn't implement `paste(_:)` — we add it informally via
    /// `NSStandardKeyBindingResponding`, so no `override`.
    @objc public func paste(_ sender: Any?) {
        guard let topic = selectedElement?.topic,
              let base64 = MindMapPasteHelper.imageBase64(from: NSPasteboard.general)
        else { return }
        undoableSetAttribute(topic, key: TopicAttribute.image, value: base64)
    }

    /// Enable the system Edit > Paste menu item when we can actually
    /// consume the pasteboard. Without this, the menu would be perma-grey
    /// because NSView's default has no paste action installed.
    @objc public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(paste(_:)) {
            return selectedElement != nil
                && MindMapPasteHelper.imageBase64(from: NSPasteboard.general) != nil
        }
        return true
    }
}

/// Pure-logic pasteboard reader for the canvas paste path. Lives outside
/// the view so the "what's worth pasting" logic is unit-testable without
/// instantiating an NSView. Currently handles image-bearing pasteboards;
/// future work (#93 topic subtree) plugs in here too.
public enum MindMapPasteHelper {
    /// Extract a base64-encoded PNG from the pasteboard if it carries any
    /// representable image. Returns nil when the pasteboard has no image.
    /// PNG is the format `mmd.image` already round-trips through
    /// (FreeMind imports + context-menu Set Image both store PNG base64).
    public static func imageBase64(from pasteboard: NSPasteboard) -> String? {
        // Direct PNG data is the cheapest path — skip image decode round-trip.
        if let pngData = pasteboard.data(forType: .png) {
            return pngData.base64EncodedString()
        }
        // Fall back to NSImage so JPEG/TIFF/PDF screenshots all become PNG.
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return png.base64EncodedString()
    }
}
