import AppKit

/// The preview-mode picker (editor / side-by-side / stacked, and optionally a
/// preview-only "reading" view) shared by the markdown and plantuml editor
/// footers.
public enum PreviewModeControl {
    public static func make(target: AnyObject, action: Selector,
                            includePreviewOnly: Bool = false) -> NSSegmentedControl {
        func img(_ name: String) -> NSImage { NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage() }
        var images = [img("doc.plaintext"), img("rectangle.split.2x1"), img("rectangle.split.1x2")]
        if includePreviewOnly { images.append(img("eye")) }
        let c = NSSegmentedControl(images: images, trackingMode: .selectOne, target: target, action: action)
        c.segmentStyle = .texturedRounded
        c.controlSize = .small
        c.translatesAutoresizingMaskIntoConstraints = false
        c.setToolTip("Editor only", forSegment: 0)
        c.setToolTip("Preview side-by-side", forSegment: 1)
        c.setToolTip("Preview stacked", forSegment: 2)
        if includePreviewOnly { c.setToolTip("Reading view (preview only)", forSegment: 3) }
        return c
    }
}
