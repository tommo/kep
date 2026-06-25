import CoreGraphics

/// Pure-logic helper for "drop between siblings" hit-testing during a
/// topic drag. Given the visually-sorted Y ranges of the source's
/// siblings and a probe Y, returns the gap index the probe falls into
/// (so caller can map it back to a children-array insertion index).
///
/// Lives outside MindMapView so the geometry math is unit-testable
/// without standing up an offscreen view + layout pass.
public enum MindMapDragGap {

    public struct YRange: Equatable {
        public let minY: CGFloat
        public let maxY: CGFloat
        public init(_ minY: CGFloat, _ maxY: CGFloat) {
            self.minY = minY
            self.maxY = maxY
        }
    }

    /// Returns the index of the gap that contains `probeY`, where the
    /// returned value `i` means "insert before the i-th range". Returns
    /// nil when the probe is inside a range (drop-onto-topic territory)
    /// or outside the bounding extents.
    /// Ranges must be sorted by `minY` ascending.
    public static func gapIndex(for probeY: CGFloat, sortedRanges: [YRange]) -> Int? {
        guard !sortedRanges.isEmpty else { return nil }
        // Inside one of the existing topics → not a gap drop.
        for r in sortedRanges where probeY >= r.minY && probeY <= r.maxY {
            return nil
        }
        // Above the first → insert at 0.
        if probeY < sortedRanges[0].minY { return 0 }
        // Between adjacent siblings.
        for i in 0..<sortedRanges.count - 1 {
            let upper = sortedRanges[i].maxY
            let lower = sortedRanges[i + 1].minY
            if probeY > upper && probeY < lower { return i + 1 }
        }
        // Below the last → insert at end.
        if probeY > sortedRanges.last!.maxY { return sortedRanges.count }
        return nil
    }
}
