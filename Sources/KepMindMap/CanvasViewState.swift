import Foundation

/// Per-document canvas view state — zoom, pan (clip origin in content space),
/// and the selected node's outline path. Codable so the app layer can persist
/// it per file across launches. Decoupled from any storage: MindMapView reads
/// it via `loadViewState` and writes it via `saveViewState`, set by the host.
public struct CanvasViewState: Codable, Equatable, Sendable {
    public var zoom: Double
    public var originX: Double
    public var originY: Double
    public var selectedPath: String?

    public init(zoom: Double, originX: Double, originY: Double, selectedPath: String?) {
        self.zoom = zoom
        self.originX = originX
        self.originY = originY
        self.selectedPath = selectedPath
    }
}
