import AppKit

/// Pasteboard → PNG base64, shared by the mind-map canvas paste and the
/// markdown editor's image paste/drop.
public enum PasteboardImage {
    /// Extract image data from `pasteboard` as base64 PNG. Prefers raw PNG data
    /// (cheapest), else decodes any NSImage (JPEG/TIFF/PDF screenshot) to PNG.
    public static func base64(from pasteboard: NSPasteboard) -> String? {
        if let pngData = pasteboard.data(forType: .png) {
            return pngData.base64EncodedString()
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:])
        else { return nil }
        return png.base64EncodedString()
    }
}
