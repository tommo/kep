import Foundation

/// Actions offered on a rendered-preview right-click menu. Shared so the
/// WKWebView subclasses that host the markdown / PlantUML previews can build
/// their context menus from one tested spec instead of hand-rolling
/// NSMenuItems inline.
public enum PreviewMenuAction: String, CaseIterable, Sendable {
    case refresh
    case copySVG
    case copyPNG
    case copyASCII
    case copyScript
    case copyHTML
    case export
    case exportHTML
    case exportPDF
    case viewSource
}

public struct PreviewMenuItem: Equatable {
    public let action: PreviewMenuAction
    public let title: String
    /// Disabled items still show (so the capability is discoverable) but
    /// can't be invoked — e.g. Copy/Export before anything has rendered.
    public let isEnabled: Bool

    public init(action: PreviewMenuAction, title: String, isEnabled: Bool) {
        self.action = action
        self.title = title
        self.isEnabled = isEnabled
    }
}

public enum PreviewContextMenu {

    /// Items for the PlantUML diagram preview. Copy/Export need a rendered
    /// diagram; Refresh is always available.
    public static func plantUML(hasRenderedDiagram: Bool) -> [PreviewMenuItem] {
        [
            PreviewMenuItem(action: .refresh, title: "Refresh Preview", isEnabled: true),
            PreviewMenuItem(action: .copySVG, title: "Copy as SVG", isEnabled: hasRenderedDiagram),
            PreviewMenuItem(action: .copyPNG, title: "Copy as PNG", isEnabled: hasRenderedDiagram),
            PreviewMenuItem(action: .copyASCII, title: "Copy as ASCII", isEnabled: hasRenderedDiagram),
            // Copy Script needs no render — the source is always available.
            PreviewMenuItem(action: .copyScript, title: "Copy Script", isEnabled: true),
            PreviewMenuItem(action: .export, title: "Export Diagram…", isEnabled: hasRenderedDiagram),
        ]
    }

    /// Items for the markdown HTML preview. Refresh re-renders; View Source
    /// puts the caret back in the editor.
    public static func markdown() -> [PreviewMenuItem] {
        [
            PreviewMenuItem(action: .refresh, title: "Refresh Preview", isEnabled: true),
            PreviewMenuItem(action: .copyHTML, title: "Copy as HTML", isEnabled: true),
            PreviewMenuItem(action: .exportHTML, title: "Export as HTML…", isEnabled: true),
            PreviewMenuItem(action: .exportPDF, title: "Export as PDF…", isEnabled: true),
            PreviewMenuItem(action: .viewSource, title: "Focus Editor", isEnabled: true),
        ]
    }
}
