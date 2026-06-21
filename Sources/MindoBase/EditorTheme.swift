import AppKit
import MindoCore

/// Per-appearance color overrides for the editor syntax palette. Each role is
/// an optional `#RRGGBB` — nil means "use the built-in value for this role".
public struct EditorThemeColors: Codable, Equatable, Sendable {
    public var text: String?
    public var keyword: String?
    public var string: String?
    public var comment: String?
    public var link: String?
    public var punctuation: String?

    public init(text: String? = nil, keyword: String? = nil, string: String? = nil,
                comment: String? = nil, link: String? = nil, punctuation: String? = nil) {
        self.text = text; self.keyword = keyword; self.string = string
        self.comment = comment; self.link = link; self.punctuation = punctuation
    }
}

/// The user's custom editor theme: an enable flag plus light/dark overrides.
/// Persisted as JSON; resolved on top of the built-in [SyntaxPalette].
public struct EditorTheme: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var light: EditorThemeColors
    public var dark: EditorThemeColors

    public init(enabled: Bool = false,
                light: EditorThemeColors = EditorThemeColors(),
                dark: EditorThemeColors = EditorThemeColors()) {
        self.enabled = enabled
        self.light = light
        self.dark = dark
    }

    public static let `default` = EditorTheme()
}

public extension Notification.Name {
    /// Posted when the custom editor theme changes — editors re-highlight.
    static let editorThemeChanged = Notification.Name("mindo.editorThemeChanged")
}

/// Loads/saves the custom [EditorTheme] and broadcasts changes.
public enum EditorThemeStore {
    public static var current: EditorTheme {
        guard let data = UserDefaults.standard.data(forKey: PrefKeys.editorTheme),
              let theme = try? JSONDecoder().decode(EditorTheme.self, from: data)
        else { return .default }
        return theme
    }

    public static func save(_ theme: EditorTheme) {
        if let data = try? JSONEncoder().encode(theme) {
            UserDefaults.standard.set(data, forKey: PrefKeys.editorTheme)
        }
        NotificationCenter.default.post(name: .editorThemeChanged, object: nil)
    }
}

public extension SyntaxPalette {
    /// This palette with any non-nil overrides from `colors` applied.
    func applying(_ colors: EditorThemeColors) -> SyntaxPalette {
        func c(_ hex: String?, _ fallback: NSColor) -> NSColor {
            hex.flatMap(NSColor.init(hexString:)) ?? fallback
        }
        return SyntaxPalette(
            text:        c(colors.text, text),
            keyword:     c(colors.keyword, keyword),
            string:      c(colors.string, string),
            comment:     c(colors.comment, comment),
            link:        c(colors.link, link),
            punctuation: c(colors.punctuation, punctuation)
        )
    }
}
