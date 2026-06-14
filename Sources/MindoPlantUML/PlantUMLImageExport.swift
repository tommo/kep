import AppKit

/// Pure-ish helpers for "Export diagram to image file…" on the PlantUML
/// editor. The format/extension/filename logic is fully deterministic and
/// unit-tested; the rasterization wraps AppKit's NSImage and is guarded so
/// bad input returns nil rather than producing a corrupt file.
public enum PlantUMLImageExport {

    public enum Format: String, CaseIterable {
        case svg
        case png
        public var fileExtension: String { rawValue }
    }

    /// Default save-panel filename: the source `.puml`'s base name with the
    /// chosen image extension, or "diagram.<ext>" for an unsaved document.
    public static func defaultFilename(sourceURL: URL?, format: Format) -> String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent
        let stem = (base?.isEmpty == false ? base! : "diagram")
        return stem + "." + format.fileExtension
    }

    /// Bytes to write for `format`, given the last rendered SVG. SVG is the
    /// data as-is; PNG is rasterized via NSImage. Returns nil when there's
    /// no usable SVG or rasterization fails.
    public static func data(forSVG svgData: Data?, format: Format) -> Data? {
        guard let svgData, !svgData.isEmpty else { return nil }
        switch format {
        case .svg: return svgData
        case .png: return pngData(fromSVGData: svgData)
        }
    }

    /// Rasterize SVG bytes to PNG via NSImage → NSBitmapImageRep. nil when
    /// the data isn't a renderable image.
    public static func pngData(fromSVGData svgData: Data) -> Data? {
        guard let image = NSImage(data: svgData) else { return nil }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
