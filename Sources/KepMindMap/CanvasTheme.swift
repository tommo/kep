import AppKit
import KepBase
import KepCore

/// User overrides for the mind-map canvas colors — the editable layer behind
/// `ThemeChoice.custom`. Each role is an optional `#RRGGBB`; nil keeps the
/// base theme's value. Mirrors the editor `EditorTheme` pattern.
public struct CanvasThemeColors: Codable, Equatable, Sendable {
    public var paper: String?
    public var rootFill: String?
    public var rootBorder: String?
    public var rootText: String?
    public var firstFill: String?
    public var firstBorder: String?
    public var firstText: String?
    public var otherFill: String?
    public var otherBorder: String?
    public var otherText: String?
    public var connector: String?

    public init(paper: String? = nil, rootFill: String? = nil, rootBorder: String? = nil,
                rootText: String? = nil, firstFill: String? = nil, firstBorder: String? = nil,
                firstText: String? = nil, otherFill: String? = nil, otherBorder: String? = nil,
                otherText: String? = nil, connector: String? = nil) {
        self.paper = paper; self.rootFill = rootFill; self.rootBorder = rootBorder
        self.rootText = rootText; self.firstFill = firstFill; self.firstBorder = firstBorder
        self.firstText = firstText; self.otherFill = otherFill; self.otherBorder = otherBorder
        self.otherText = otherText; self.connector = connector
    }
}

public extension Notification.Name {
    /// Posted when the custom canvas theme changes.
    static let canvasThemeChanged = Notification.Name("kep.canvasThemeChanged")
}

/// Loads/saves the custom canvas colors and broadcasts changes.
public enum CanvasThemeStore {
    public static var current: CanvasThemeColors {
        guard let data = UserDefaults.standard.data(forKey: PrefKeys.canvasTheme),
              let c = try? JSONDecoder().decode(CanvasThemeColors.self, from: data)
        else { return CanvasThemeColors() }
        return c
    }

    public static func save(_ colors: CanvasThemeColors) {
        if let data = try? JSONEncoder().encode(colors) {
            UserDefaults.standard.set(data, forKey: PrefKeys.canvasTheme)
        }
        NotificationCenter.default.post(name: .canvasThemeChanged, object: nil)
    }
}

public extension MindMapTheme {
    /// This theme with any non-nil canvas-color overrides applied.
    func applying(_ colors: CanvasThemeColors) -> MindMapTheme {
        var t = self
        func set(_ hex: String?, _ keyPath: WritableKeyPath<MindMapTheme, NSColor>) {
            if let c = hex.flatMap(NSColor.init(hexString:)) { t[keyPath: keyPath] = c }
        }
        set(colors.paper, \.paperColor)
        set(colors.rootFill, \.rootFillColor)
        set(colors.rootBorder, \.rootBorderColor)
        set(colors.rootText, \.rootTextColor)
        set(colors.firstFill, \.firstLevelFillColor)
        set(colors.firstBorder, \.firstLevelBorderColor)
        set(colors.firstText, \.firstLevelTextColor)
        set(colors.otherFill, \.otherLevelFillColor)
        set(colors.otherBorder, \.otherLevelBorderColor)
        set(colors.otherText, \.otherLevelTextColor)
        set(colors.connector, \.connectorColor)
        return t
    }

    /// The custom canvas theme: the light base with the user's overrides.
    static var custom: MindMapTheme { light.applying(CanvasThemeStore.current) }
}
