import AppKit
import KepCore

/// App-wide chrome appearance override. "System" defers to the macOS setting
/// (the default); Light/Dark force the whole app regardless. This is the
/// foundation of the unified theming work — it sets `NSApp.appearance`, which
/// every AppKit/SwiftUI surface in the window inherits.
public enum AppAppearance: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// The AppKit appearance to install, or nil to follow the system.
    public var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        }
    }

    /// The persisted choice (defaults to `.system` when unset/invalid).
    public static var current: AppAppearance {
        PrefKeys.string(PrefKeys.appAppearance).flatMap(AppAppearance.init(rawValue:)) ?? .system
    }

    /// Install this appearance on the running app. nil appearance = follow system.
    @MainActor
    public func apply() {
        NSApp.appearance = nsAppearance
    }

    /// Apply the persisted choice — call at launch.
    @MainActor
    public static func applyCurrent() {
        current.apply()
    }
}
