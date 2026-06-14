import Foundation

/// Pure decisions backing the PlantUML preview, pulled out of the AppKit
/// coordinator so the bug-prone bits — "don't throw away the last good
/// render on an error", "re-render when dark mode flips", "did we have
/// anything to copy" — are unit-testable without a WKWebView or a live
/// PlantUML process.
public enum PlantUMLPreviewState {

    /// The SVG cache to keep after a render attempt. A failed render yields
    /// `rendered == nil`; in that case we hold on to the previously cached
    /// good SVG instead of wiping it, so Copy SVG/PNG still works while the
    /// source has a transient error. (The bug: the cache was overwritten
    /// unconditionally, nilling a good diagram on the first typo.)
    public static func updatedCache(current: Data?, rendered: Data?) -> Data? {
        rendered ?? current
    }

    /// Whether `updateNSView` should kick a re-render. Previously it only
    /// looked at text changes, so toggling the app's dark mode re-highlighted
    /// the source but left the preview rendered for the old theme (rank 20).
    public static func shouldRerender(textChanged: Bool, darkModeChanged: Bool) -> Bool {
        textChanged || darkModeChanged
    }
}

/// Result of a Copy SVG / Copy PNG request — lets the view give feedback
/// (beep + footer note) instead of silently doing nothing when there's no
/// rendered diagram yet.
public enum DiagramCopyResult: Equatable {
    case copied
    case nothingToCopy
}

public enum PlantUMLClipboard {
    /// Whether a copy can proceed given the cached SVG. `nil`/empty data —
    /// no successful render yet — is `.nothingToCopy`.
    public static func outcome(for data: Data?) -> DiagramCopyResult {
        guard let data, !data.isEmpty else { return .nothingToCopy }
        return .copied
    }
}
