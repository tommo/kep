import AppKit

/// Visual tokens for the mind-map canvas. Mirrors the most important properties from
/// `MindMapTheme` in `mindmap-panel`. Defaults match the Java `LightTheme`.
public struct MindMapTheme: Sendable {
    public var paperColor: NSColor

    // Per-level fills
    public var rootFillColor: NSColor
    public var rootBorderColor: NSColor
    public var rootTextColor: NSColor
    public var firstLevelFillColor: NSColor
    public var firstLevelBorderColor: NSColor
    public var firstLevelTextColor: NSColor
    public var otherLevelFillColor: NSColor
    public var otherLevelBorderColor: NSColor
    public var otherLevelTextColor: NSColor

    // Connector
    public var connectorColor: NSColor
    public var connectorWidth: CGFloat

    // Geometry
    public var cornerRadius: CGFloat
    public var textInsets: NSEdgeInsets
    public var verticalGap: CGFloat
    public var horizontalGap: CGFloat
    public var dropShadowOffset: CGSize
    public var dropShadowOpacity: CGFloat

    // Selection
    public var selectionColor: NSColor
    public var selectionWidth: CGFloat

    public var fontName: String
    public var fontSizeRoot: CGFloat
    public var fontSizeFirstLevel: CGFloat
    public var fontSizeOther: CGFloat

    public init(
        paperColor: NSColor,
        rootFillColor: NSColor,
        rootBorderColor: NSColor,
        rootTextColor: NSColor,
        firstLevelFillColor: NSColor,
        firstLevelBorderColor: NSColor,
        firstLevelTextColor: NSColor,
        otherLevelFillColor: NSColor,
        otherLevelBorderColor: NSColor,
        otherLevelTextColor: NSColor,
        connectorColor: NSColor,
        connectorWidth: CGFloat = 1.5,
        cornerRadius: CGFloat = 8,
        textInsets: NSEdgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12),
        verticalGap: CGFloat = 14,
        horizontalGap: CGFloat = 60,
        dropShadowOffset: CGSize = CGSize(width: 1, height: -1),
        dropShadowOpacity: CGFloat = 0.18,
        selectionColor: NSColor = .systemBlue,
        selectionWidth: CGFloat = 2,
        fontName: String = "HelveticaNeue",
        fontSizeRoot: CGFloat = 18,
        fontSizeFirstLevel: CGFloat = 14,
        fontSizeOther: CGFloat = 12
    ) {
        self.paperColor = paperColor
        self.rootFillColor = rootFillColor
        self.rootBorderColor = rootBorderColor
        self.rootTextColor = rootTextColor
        self.firstLevelFillColor = firstLevelFillColor
        self.firstLevelBorderColor = firstLevelBorderColor
        self.firstLevelTextColor = firstLevelTextColor
        self.otherLevelFillColor = otherLevelFillColor
        self.otherLevelBorderColor = otherLevelBorderColor
        self.otherLevelTextColor = otherLevelTextColor
        self.connectorColor = connectorColor
        self.connectorWidth = connectorWidth
        self.cornerRadius = cornerRadius
        self.textInsets = textInsets
        self.verticalGap = verticalGap
        self.horizontalGap = horizontalGap
        self.dropShadowOffset = dropShadowOffset
        self.dropShadowOpacity = dropShadowOpacity
        self.selectionColor = selectionColor
        self.selectionWidth = selectionWidth
        self.fontName = fontName
        self.fontSizeRoot = fontSizeRoot
        self.fontSizeFirstLevel = fontSizeFirstLevel
        self.fontSizeOther = fontSizeOther
    }

    // Clean, professional default: flat fills, a single dark accent for the
    // root, white nodes with hairline neutral borders, thin grey connectors,
    // and the system font. No coloured per-level fills or heavy shadow.
    public static let light = MindMapTheme(
        paperColor: NSColor(white: 0.985, alpha: 1),
        rootFillColor: NSColor(red: 0.17, green: 0.19, blue: 0.22, alpha: 1),   // slate
        rootBorderColor: NSColor(red: 0.17, green: 0.19, blue: 0.22, alpha: 1),
        rootTextColor: .white,
        firstLevelFillColor: .white,
        firstLevelBorderColor: NSColor(white: 0.80, alpha: 1),
        firstLevelTextColor: NSColor(white: 0.12, alpha: 1),
        otherLevelFillColor: .white,
        otherLevelBorderColor: NSColor(white: 0.88, alpha: 1),
        otherLevelTextColor: NSColor(white: 0.25, alpha: 1),
        connectorColor: NSColor(white: 0.78, alpha: 1),
        cornerRadius: 6,
        dropShadowOpacity: 0.08,
        fontName: systemFontToken
    )

    public static let dark = MindMapTheme(
        paperColor: NSColor(white: 0.12, alpha: 1),
        rootFillColor: NSColor(white: 0.90, alpha: 1),                          // light slate on dark
        rootBorderColor: NSColor(white: 0.90, alpha: 1),
        rootTextColor: NSColor(white: 0.10, alpha: 1),
        firstLevelFillColor: NSColor(white: 0.18, alpha: 1),
        firstLevelBorderColor: NSColor(white: 0.34, alpha: 1),
        firstLevelTextColor: NSColor(white: 0.93, alpha: 1),
        otherLevelFillColor: NSColor(white: 0.15, alpha: 1),
        otherLevelBorderColor: NSColor(white: 0.28, alpha: 1),
        otherLevelTextColor: NSColor(white: 0.82, alpha: 1),
        connectorColor: NSColor(white: 0.40, alpha: 1),
        cornerRadius: 6,
        dropShadowOpacity: 0.0,
        fontName: systemFontToken
    )

    public static let classic = MindMapTheme(
        paperColor: NSColor(red: 0.95, green: 0.94, blue: 0.86, alpha: 1),
        rootFillColor: NSColor(red: 0.85, green: 0.40, blue: 0.20, alpha: 1),
        rootBorderColor: NSColor(red: 0.60, green: 0.20, blue: 0.10, alpha: 1),
        rootTextColor: .white,
        firstLevelFillColor: NSColor(red: 1.00, green: 0.92, blue: 0.65, alpha: 1),
        firstLevelBorderColor: NSColor(red: 0.70, green: 0.55, blue: 0.30, alpha: 1),
        firstLevelTextColor: NSColor(white: 0.10, alpha: 1),
        otherLevelFillColor: NSColor(red: 1.00, green: 0.97, blue: 0.85, alpha: 1),
        otherLevelBorderColor: NSColor(red: 0.75, green: 0.65, blue: 0.45, alpha: 1),
        otherLevelTextColor: NSColor(white: 0.15, alpha: 1),
        connectorColor: NSColor(red: 0.55, green: 0.40, blue: 0.20, alpha: 1)
    )

    func fillColor(forLevel level: Int) -> NSColor {
        switch level {
        case 0: return rootFillColor
        case 1: return firstLevelFillColor
        default: return otherLevelFillColor
        }
    }

    func borderColor(forLevel level: Int) -> NSColor {
        switch level {
        case 0: return rootBorderColor
        case 1: return firstLevelBorderColor
        default: return otherLevelBorderColor
        }
    }

    func textColor(forLevel level: Int) -> NSColor {
        switch level {
        case 0: return rootTextColor
        case 1: return firstLevelTextColor
        default: return otherLevelTextColor
        }
    }

    /// Sentinel `fontName` meaning "use the system UI font" — picks a weight
    /// per level for a clean, modern look instead of a fixed-weight typeface.
    public static let systemFontToken = ".systemUI"

    func font(forLevel level: Int) -> NSFont {
        let size: CGFloat = level == 0 ? fontSizeRoot : (level == 1 ? fontSizeFirstLevel : fontSizeOther)
        if fontName == Self.systemFontToken {
            let weight: NSFont.Weight = level == 0 ? .semibold : (level == 1 ? .medium : .regular)
            return .systemFont(ofSize: size, weight: weight)
        }
        return NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size)
    }
}
