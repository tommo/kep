import AppKit

/// The 3-segment preview-mode picker (no preview / side-by-side / stacked)
/// shared by the markdown and plantuml editor footers.
public enum PreviewModeControl {
    public static func make(target: AnyObject, action: Selector) -> NSSegmentedControl {
        func img(_ name: String) -> NSImage { NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage() }
        let c = NSSegmentedControl(
            images: [img("doc.plaintext"), img("rectangle.split.2x1"), img("rectangle.split.1x2")],
            trackingMode: .selectOne, target: target, action: action)
        c.segmentStyle = .texturedRounded
        c.controlSize = .small
        c.translatesAutoresizingMaskIntoConstraints = false
        c.setToolTip("No preview", forSegment: 0)
        c.setToolTip("Preview side-by-side", forSegment: 1)
        c.setToolTip("Preview stacked", forSegment: 2)
        return c
    }
}
