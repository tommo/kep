import AppKit
import SwiftUI

/// Single point of icon lookup for the app. Mirrors the role of
/// `FontIconManager` from `mindolph-base`, scoped to what we actually need:
/// take an icon name (SF Symbol or a FontAwesome-style alias), return a
/// tinted `NSImage`.
///
/// Resolution order:
///   1. SF Symbol with the literal name (`NSImage(systemSymbolName:)`).
///   2. FontAwesome → SF Symbol alias map (`faToSF`).
///   3. Fallback: `questionmark.circle` so the UI stays renderable.
///
/// Bundled FontAwesome.otf isn't shipped yet (Mindolph used FontAwesomeFX);
/// when we add it later, the alias map switches over to font-based rendering
/// in a follow-up iteration.
public final class FontIcon {
    public static let shared = FontIcon()

    private struct CacheKey: Hashable {
        let name: String
        let size: CGFloat
        /// Color identity — catalog colors (`.labelColor`, etc.) refuse RGB
        /// component access, so we just compare by reference identity for
        /// catalog colors and fall back to RGB for plain ones.
        let colorKey: String
    }

    private var cache: [CacheKey: NSImage] = [:]
    private let cacheLock = NSLock()

    public init() {}

    /// Look up an icon by name and return a tinted `NSImage` sized for `size`.
    /// Caches the result so repeated lookups are cheap.
    public func image(named name: String, size: CGFloat = 16, color: NSColor = .labelColor) -> NSImage {
        let key = CacheKey(name: name, size: size, colorKey: Self.colorKey(for: color))
        cacheLock.lock()
        if let cached = cache[key] { cacheLock.unlock(); return cached }
        cacheLock.unlock()

        let resolvedName = Self.faToSF[name] ?? name
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .regular)
        let base = NSImage(systemSymbolName: resolvedName, accessibilityDescription: name)?
            .withSymbolConfiguration(config)
            ?? NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: name)?
                .withSymbolConfiguration(config)
            ?? NSImage()

        let tinted = Self.tinted(image: base, color: color)
        cacheLock.lock()
        cache[key] = tinted
        cacheLock.unlock()
        return tinted
    }

    /// SwiftUI bridge — returns an `Image` view tinted appropriately.
    public func swiftUIImage(named name: String, size: CGFloat = 16, color: Color = .primary) -> Image {
        // Resolve to SF Symbol name (or fallback) and let SwiftUI handle styling.
        let symbolName = NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
            ? name
            : (Self.faToSF[name] ?? "questionmark.circle")
        return Image(systemName: symbolName)
    }

    /// Strip the cache. Useful for tests + theme changes that swap accent colors.
    public func clearCache() {
        cacheLock.lock()
        cache.removeAll()
        cacheLock.unlock()
    }

    /// Number of cached entries — exposed for tests so they can assert
    /// caching actually short-circuits.
    public var cacheCount: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return cache.count
    }

    // MARK: - FontAwesome → SF Symbol map

    /// Best-effort mapping. Mindolph's UI uses many FontAwesome icons; we
    /// route the most common ones to closest SF Symbol equivalents so existing
    /// code can call `FontIcon.shared.image(named: "fa-trash")` without
    /// caring whether SF Symbols already covers it.
    public static let faToSF: [String: String] = [
        "fa-bold": "bold",
        "fa-italic": "italic",
        "fa-code": "chevron.left.forwardslash.chevron.right",
        "fa-link": "link",
        "fa-image": "photo",
        "fa-list-ul": "list.bullet",
        "fa-list-ol": "list.number",
        "fa-quote-left": "text.quote",
        "fa-h": "h.square",
        "fa-h1": "1.square",
        "fa-h2": "2.square",
        "fa-h3": "3.square",
        "fa-h4": "4.square",
        "fa-h5": "5.square",
        "fa-h6": "6.square",
        "fa-trash": "trash",
        "fa-trash-o": "trash",
        "fa-plus": "plus",
        "fa-minus": "minus",
        "fa-search": "magnifyingglass",
        "fa-folder": "folder",
        "fa-folder-open": "folder.fill",
        "fa-file": "doc",
        "fa-file-o": "doc",
        "fa-file-text": "doc.text",
        "fa-file-image-o": "photo",
        "fa-cog": "gear",
        "fa-cogs": "gearshape.2",
        "fa-gear": "gear",
        "fa-info-circle": "info.circle",
        "fa-question-circle": "questionmark.circle",
        "fa-warning": "exclamationmark.triangle",
        "fa-exclamation-triangle": "exclamationmark.triangle",
        "fa-bug": "ant",
        "fa-comment": "bubble.left",
        "fa-comments": "bubble.left.and.bubble.right",
        "fa-star": "star",
        "fa-star-o": "star",
        "fa-bookmark": "bookmark",
        "fa-tag": "tag",
        "fa-tags": "tag.fill",
        "fa-rocket": "paperplane.fill",
        "fa-magic": "wand.and.stars",
        "fa-undo": "arrow.uturn.backward",
        "fa-redo": "arrow.uturn.forward",
        "fa-save": "tray.and.arrow.down",
        "fa-print": "printer",
        "fa-download": "arrow.down.circle",
        "fa-upload": "arrow.up.circle",
        "fa-refresh": "arrow.triangle.2.circlepath",
        "fa-eye": "eye",
        "fa-eye-slash": "eye.slash",
        "fa-lock": "lock",
        "fa-unlock": "lock.open",
        "fa-bars": "line.horizontal.3",
        "fa-arrows": "arrow.up.and.down.and.arrow.left.and.right",
        "fa-arrow-up": "arrow.up",
        "fa-arrow-down": "arrow.down",
        "fa-arrow-left": "arrow.left",
        "fa-arrow-right": "arrow.right",
        "fa-check": "checkmark",
        "fa-times": "xmark",
        "fa-close": "xmark",
        "fa-pencil": "pencil",
        "fa-edit": "pencil.line",
        "fa-copy": "doc.on.doc",
        "fa-cut": "scissors",
        "fa-clipboard": "list.clipboard",
        "fa-paperclip": "paperclip",
        "fa-sticky-note": "note.text",
        "fa-sitemap": "rectangle.connected.to.line.below",
    ]

    /// Stable string key for a color — convert to sRGB before reading
    /// components so catalog colors like `.labelColor` don't throw.
    private static func colorKey(for color: NSColor) -> String {
        if let rgb = color.usingColorSpace(.sRGB) {
            return String(format: "%.4f,%.4f,%.4f,%.4f",
                          rgb.redComponent, rgb.greenComponent,
                          rgb.blueComponent, rgb.alphaComponent)
        }
        return "\(ObjectIdentifier(color).hashValue)"
    }

    private static func tinted(image: NSImage, color: NSColor) -> NSImage {
        guard image.size.width > 0 else { return image }
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        result.unlockFocus()
        result.isTemplate = false
        return result
    }
}
