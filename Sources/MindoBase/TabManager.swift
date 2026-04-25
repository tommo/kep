import Foundation

/// MRU (most-recently-used) stack of identifiers. Mirrors the role of
/// Mindolph's `TabManager`: drives "previous tab" / "next tab" navigation
/// based on activation order rather than tab-bar layout order.
public final class TabManager<ID: Hashable> {
    private var order: [ID] = []   // newest first

    public init() {}

    public var count: Int { order.count }
    public var ids: [ID] { order }
    public var activeID: ID? { order.first }
    public var previousID: ID? { order.dropFirst().first }

    /// Mark `id` as the active (most recently used) tab.
    public func activate(_ id: ID) {
        order.removeAll { $0 == id }
        order.insert(id, at: 0)
    }

    /// Forget about a tab (typically because it closed).
    public func remove(_ id: ID) {
        order.removeAll { $0 == id }
    }

    /// MRU index — 0 == active, 1 == previous, etc. Returns nil when not present.
    public func mruIndex(of id: ID) -> Int? {
        order.firstIndex(of: id)
    }

    /// Cycle to the next MRU tab after `current`. Wraps around. Returns nil
    /// when the manager has fewer than 2 entries.
    public func nextMRU(after current: ID) -> ID? {
        guard order.count > 1 else { return nil }
        guard let idx = order.firstIndex(of: current) else { return order.first }
        let next = (idx + 1) % order.count
        return order[next]
    }

    /// Cycle to the previous MRU tab before `current`. Wraps around.
    public func previousMRU(before current: ID) -> ID? {
        guard order.count > 1 else { return nil }
        guard let idx = order.firstIndex(of: current) else { return order.first }
        let prev = (idx - 1 + order.count) % order.count
        return order[prev]
    }

    public func clear() { order.removeAll() }
}
