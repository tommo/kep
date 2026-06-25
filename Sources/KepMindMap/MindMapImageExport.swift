import AppKit
import KepModel

/// PNG + SVG export for the mindmap canvas. Mirrors the role of
/// PNGImageExporter / SVGImageExporter from `mindolph-mindmap`.
public enum MindMapImageExport {

    public enum ExportError: Error {
        case noContent
        case bitmapFailed
        case writeFailed(String)
    }

    // MARK: - PNG

    /// Render `map` to a PNG file via an offscreen MindMapView. `scale` lets
    /// the caller pick a Retina-quality dump (default 2 = @2x).
    public static func exportPNG(_ map: MindMap, theme: MindMapTheme = .light, scale: CGFloat = 2.0, to url: URL) throws {
        let bitmap = try makeBitmap(map: map, theme: theme, scale: scale)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.bitmapFailed
        }
        do { try data.write(to: url, options: .atomic) }
        catch { throw ExportError.writeFailed(error.localizedDescription) }
    }

    /// Build the bitmap separately so callers (e.g. preview UI, copy-to-
    /// pasteboard) can reuse it without going through the file system.
    public static func makeBitmap(map: MindMap, theme: MindMapTheme = .light, scale: CGFloat = 2.0) throws -> NSBitmapImageRep {
        // Lay out at scale=1 in an offscreen canvas, then render at the
        // requested scale via cacheDisplay's pixelsHigh / pixelsWide.
        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.theme = theme
        view.display(map: map)
        // Tighten the view's frame to its content bounds so the PNG isn't
        // padded with blank canvas.
        let bounds = view.contentBounds
        guard bounds.width > 0, bounds.height > 0 else { throw ExportError.noContent }
        let pad: CGFloat = 16
        let frame = bounds.insetBy(dx: -pad, dy: -pad)
        view.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
        // Reposition every element so the union sits at (pad, pad).
        let dx = pad - bounds.minX
        let dy = pad - bounds.minY
        view.rootElement?.traverse { el in
            el.frame.origin.x += dx
            el.frame.origin.y += dy
            el.subtreeBounds.origin.x += dx
            el.subtreeBounds.origin.y += dy
        }
        view.contentBounds = view.contentBounds.offsetBy(dx: dx, dy: dy)
        view.needsDisplay = true

        let pixelW = Int(ceil(frame.width  * scale))
        let pixelH = Int(ceil(frame.height * scale))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelW, pixelsHigh: pixelH,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 32
        ) else { throw ExportError.bitmapFailed }
        bitmap.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    // MARK: - Clipboard

    /// Render `map` to a PNG and place it on the pasteboard as both PNG and
    /// TIFF flavors, so any consumer (Slack, Notes, Preview…) can read it.
    /// Mirrors PlantUML's "Copy as PNG". Returns false when there's nothing
    /// to render (empty map) so the caller can give feedback. The `pasteboard`
    /// parameter is injectable for tests.
    @discardableResult
    public static func copyPNGToPasteboard(
        _ map: MindMap, theme: MindMapTheme = .light, scale: CGFloat = 2.0,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard let bitmap = try? makeBitmap(map: map, theme: theme, scale: scale),
              let png = bitmap.representation(using: .png, properties: [:]) else { return false }
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = bitmap.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        return true
    }

    /// Render `map` to vector SVG and place it on the pasteboard as a string
    /// plus a `public.svg-image` data flavor. Mirrors PlantUML's "Copy as
    /// SVG". Returns false when there's nothing to render.
    @discardableResult
    public static func copySVGToPasteboard(
        _ map: MindMap, theme: MindMapTheme = .light,
        pasteboard: NSPasteboard = .general
    ) -> Bool {
        guard let svg = try? makeSVG(map: map, theme: theme) else { return false }
        pasteboard.clearContents()
        pasteboard.setData(Data(svg.utf8), forType: NSPasteboard.PasteboardType("public.svg-image"))
        pasteboard.setString(svg, forType: .string)
        return true
    }

    // MARK: - PDF

    /// Vector PDF export. Renders the offscreen MindMapView through
    /// `dataWithPDF(inside:)` so every shape and glyph is preserved as
    /// vector geometry — resolution-independent and printable.
    public static func exportPDF(_ map: MindMap, theme: MindMapTheme = .light, to url: URL) throws {
        let data = try makePDFData(map: map, theme: theme)
        do { try data.write(to: url, options: .atomic) }
        catch { throw ExportError.writeFailed(error.localizedDescription) }
    }

    /// Builds the PDF bytes without touching disk. Uses the same offscreen
    /// MindMapView + content-bounds tightening pattern as the PNG path so
    /// the PDF page snaps to the actual mindmap bounds (with a 16pt pad).
    public static func makePDFData(map: MindMap, theme: MindMapTheme = .light) throws -> Data {
        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.theme = theme
        view.display(map: map)
        let bounds = view.contentBounds
        guard bounds.width > 0, bounds.height > 0 else { throw ExportError.noContent }
        let pad: CGFloat = 16
        let frame = bounds.insetBy(dx: -pad, dy: -pad)
        view.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
        // Reposition every element so the union sits at (pad, pad) — same
        // shift the PNG path uses.
        let dx = pad - bounds.minX
        let dy = pad - bounds.minY
        view.rootElement?.traverse { el in
            el.frame.origin.x += dx
            el.frame.origin.y += dy
            el.subtreeBounds.origin.x += dx
            el.subtreeBounds.origin.y += dy
        }
        view.contentBounds = view.contentBounds.offsetBy(dx: dx, dy: dy)
        view.needsDisplay = true
        return view.dataWithPDF(inside: view.bounds)
    }

    // MARK: - Print

    /// Configure an NSPrintOperation that paints the mindmap into a single
    /// page sized to the content bounds (with the same 16pt pad the PNG/PDF
    /// paths use). Caller is responsible for calling `runOperationModal(for:
    /// delegate:didRun:contextInfo:)` or `run()` on the result.
    public static func printOperation(_ map: MindMap, theme: MindMapTheme = .light) throws -> NSPrintOperation {
        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.theme = theme
        view.display(map: map)
        let bounds = view.contentBounds
        guard bounds.width > 0, bounds.height > 0 else { throw ExportError.noContent }
        let pad: CGFloat = 16
        let frame = bounds.insetBy(dx: -pad, dy: -pad)
        view.frame = NSRect(x: 0, y: 0, width: frame.width, height: frame.height)
        let dx = pad - bounds.minX
        let dy = pad - bounds.minY
        view.rootElement?.traverse { el in
            el.frame.origin.x += dx
            el.frame.origin.y += dy
            el.subtreeBounds.origin.x += dx
            el.subtreeBounds.origin.y += dy
        }
        view.contentBounds = view.contentBounds.offsetBy(dx: dx, dy: dy)
        view.needsDisplay = true

        // Copy the shared info rather than mutate it — otherwise the .fit
        // pagination leaks into the next text/web (responder-chain) print job.
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        let op = NSPrintOperation(view: view, printInfo: info)
        // Name the job after the document so the print panel / spooler shows it.
        let name = map.root?.text.trimmingCharacters(in: .whitespacesAndNewlines)
        op.jobTitle = (name?.isEmpty == false ? name! : "Mind Map")
        return op
    }

    // MARK: - SVG

    /// Emit a vector SVG by walking the layout. Resolution-independent and
    /// trivially editable in any vector tool.
    public static func exportSVG(_ map: MindMap, theme: MindMapTheme = .light, to url: URL) throws {
        let svg = try makeSVG(map: map, theme: theme)
        do { try svg.write(to: url, atomically: true, encoding: .utf8) }
        catch { throw ExportError.writeFailed(error.localizedDescription) }
    }

    public static func makeSVG(map: MindMap, theme: MindMapTheme = .light) throws -> String {
        let view = MindMapView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        view.theme = theme
        view.display(map: map)
        guard let root = view.rootElement, view.contentBounds.width > 0 else {
            throw ExportError.noContent
        }
        let pad: CGFloat = 16
        let bounds = view.contentBounds.insetBy(dx: -pad, dy: -pad)
        var svg = ""
        svg.append("""
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(format(bounds.width))" height="\(format(bounds.height))" viewBox="\(format(bounds.minX)) \(format(bounds.minY)) \(format(bounds.width)) \(format(bounds.height))">

        """)
        // Background — paper color so the SVG renders the same regardless of host.
        svg.append("<rect x=\"\(format(bounds.minX))\" y=\"\(format(bounds.minY))\" width=\"\(format(bounds.width))\" height=\"\(format(bounds.height))\" fill=\"\(hex(theme.paperColor))\"/>\n")

        // Connectors first so topics paint over them.
        emitConnectors(root: root, theme: theme, into: &svg)
        // Topics — depth-first so deeper levels paint over their parents.
        root.traverse { el in
            emitTopic(el, theme: theme, into: &svg)
        }
        svg.append("</svg>\n")
        return svg
    }

    private static func emitTopic(_ el: MindMapElement, theme: MindMapTheme, into svg: inout String) {
        let frame = el.frame
        let level = el.level
        let fill = el.customFillColor ?? theme.fillColor(forLevel: level)
        let border = el.customBorderColor ?? theme.borderColor(forLevel: level)
        let textColor = el.customTextColor ?? theme.textColor(forLevel: level)
        let radius = theme.cornerRadius
        let font = theme.font(forLevel: level)
        svg.append("<rect x=\"\(format(frame.minX))\" y=\"\(format(frame.minY))\" width=\"\(format(frame.width))\" height=\"\(format(frame.height))\" rx=\"\(format(radius))\" ry=\"\(format(radius))\" fill=\"\(hex(fill))\" stroke=\"\(hex(border))\" stroke-width=\"1\"/>\n")
        // Centered single-line title — multi-line text would need <tspan>s
        // and word wrapping; first cut keeps it simple.
        let escaped = escape(el.topic.text.isEmpty ? "·" : el.topic.text)
        let textY = frame.midY + font.pointSize / 3   // SVG baseline tweak
        svg.append("<text x=\"\(format(frame.midX))\" y=\"\(format(textY))\" text-anchor=\"middle\" font-family=\"\(escape(font.fontName))\" font-size=\"\(format(font.pointSize))\" fill=\"\(hex(textColor))\">\(escaped)</text>\n")
    }

    private static func emitConnectors(root: MindMapElement, theme: MindMapTheme, into svg: inout String) {
        let stroke = hex(theme.connectorColor)
        let width = theme.connectorWidth
        let visit: (MindMapElement) -> Void = { _ in }
        _ = visit
        // Same recursive structure as drawConnectors in the canvas.
        func walk(_ el: MindMapElement) {
            if el.level == 0 {
                for c in el.leftChildren  { connect(parent: el, child: c, into: &svg, stroke: stroke, width: width); walk(c) }
                for c in el.rightChildren { connect(parent: el, child: c, into: &svg, stroke: stroke, width: width); walk(c) }
                return
            }
            guard !el.isCollapsed else { return }
            for c in el.children {
                connect(parent: el, child: c, into: &svg, stroke: stroke, width: width)
                walk(c)
            }
        }
        walk(root)
    }

    private static func connect(parent: MindMapElement, child: MindMapElement, into svg: inout String, stroke: String, width: CGFloat) {
        let p1: CGPoint
        let p2: CGPoint
        if child.isLeftSide {
            p1 = CGPoint(x: parent.frame.minX, y: parent.frame.midY)
            p2 = CGPoint(x: child.frame.maxX,  y: child.frame.midY)
        } else {
            p1 = CGPoint(x: parent.frame.maxX, y: parent.frame.midY)
            p2 = CGPoint(x: child.frame.minX,  y: child.frame.midY)
        }
        let midX = (p1.x + p2.x) / 2
        svg.append("<path d=\"M \(format(p1.x)) \(format(p1.y)) C \(format(midX)) \(format(p1.y)), \(format(midX)) \(format(p2.y)), \(format(p2.x)) \(format(p2.y))\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(format(width))\"/>\n")
    }

    // MARK: - Format helpers

    private static func format(_ v: CGFloat) -> String {
        // Trim noisy fractional digits so the SVG diff cleanly under VC.
        return String(format: "%.2f", Double(v))
    }

    private static func hex(_ color: NSColor) -> String {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        return String(format: "#%02X%02X%02X",
                      Int(round(rgb.redComponent   * 255)) & 0xFF,
                      Int(round(rgb.greenComponent * 255)) & 0xFF,
                      Int(round(rgb.blueComponent  * 255)) & 0xFF)
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out.append("&amp;")
            case "<": out.append("&lt;")
            case ">": out.append("&gt;")
            case "\"": out.append("&quot;")
            case "'": out.append("&apos;")
            default: out.append(ch)
            }
        }
        return out
    }
}
