import Foundation

/// Tiny debouncer for the editor coordinators. Hold one as a stored
/// property and call `schedule(after:_:)` on every input — only the last
/// call within the window actually fires. Calling `cancel()` discards any
/// pending work.
///
/// Used by PlantUML render scheduling, Markdown preview re-rendering, and
/// the find-in-files search box.
public final class Debouncer {
    private var workItem: DispatchWorkItem?
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    /// Cancel any pending work without scheduling new work.
    public func cancel() {
        workItem?.cancel()
        workItem = nil
    }

    /// Cancel any pending work and re-arm `block` to fire after `delay`.
    public func schedule(after delay: TimeInterval, _ block: @escaping @Sendable () -> Void) {
        workItem?.cancel()
        let item = DispatchWorkItem(block: block)
        workItem = item
        queue.asyncAfter(deadline: .now() + delay, execute: item)
    }
}
