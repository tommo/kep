import AppKit

/// Map of Mindolph / FreeMind emoticon names to SF Symbol equivalents so we
/// can render an inline icon next to a topic's title without shipping the
/// 408 PNGs the Java app bundles. Unknown names fall back to a generic
/// `tag` symbol so a topic with `mmd.emoticon=foobar` still renders as
/// "this topic has an emoticon" rather than nothing.
///
/// The mapping is intentionally partial — covers the most common Mindolph
/// emoticons + the FreeMind BUILTIN icons we see during import. Adding new
/// names is just an entry here.
enum MindMapEmoticon {

    /// Best-fit SF Symbol for the given emoticon name. Returns nil only when
    /// the name is empty.
    static func sfSymbolName(for raw: String) -> String? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return symbolMap[key] ?? "tag"
    }

    /// Render an SF Symbol-based icon at `pointSize`, tinted to `color`.
    /// Returns nil for an empty name.
    static func image(for raw: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
        guard let symbol = sfSymbolName(for: raw) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: raw)?
                .withSymbolConfiguration(config) else { return nil }
        let tinted = NSImage(size: base.size)
        tinted.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))
        color.set()
        NSRect(origin: .zero, size: base.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }

    /// Names worth advertising in a picker — keys of `symbolMap` whose
    /// SF Symbol equivalent is not the generic `tag` fallback.
    static let suggestedNames: [String] = symbolMap.keys.sorted()

    /// (emoticon name, SF Symbol) pairs for the visual picker grid, sorted by
    /// name. Every entry resolves to a real symbol (never the `tag`
    /// fallback), so the popover only ever shows icons the app can render.
    static let pickerItems: [(name: String, symbol: String)] =
        symbolMap.sorted { $0.key < $1.key }.map { (name: $0.key, symbol: $0.value) }

    /// Named map. Keep entries lowercased.
    private static let symbolMap: [String: String] = [
        // FreeMind BUILTIN names
        "bell":         "bell",
        "idea":         "lightbulb",
        "flag":         "flag",
        "ksmiletris":   "face.smiling",
        "smiley-neutral": "face.dashed",
        "smily_bad":    "face.dashed.fill",
        "stop":         "stop.circle",
        "stop-sign":    "stop.circle.fill",
        "yes":          "checkmark.circle",
        "button_ok":    "checkmark.circle",
        "button_cancel": "xmark.circle",
        "messagebox_warning": "exclamationmark.triangle",
        "info":         "info.circle",
        "help":         "questionmark.circle",
        "back":         "arrow.left",
        "forward":      "arrow.right",
        "up":           "arrow.up",
        "down":         "arrow.down",
        "edit":         "pencil",
        "list":         "list.bullet",
        "calendar":     "calendar",
        "clock":        "clock",
        "go":           "play.circle",
        "launch":       "paperplane.fill",
        "broken-line":  "scissors",
        "attach":       "paperclip",
        "kaddressbook": "person.crop.circle",
        "knotify":      "speaker.wave.2",
        "korn":         "envelope",
        "password":     "lock",
        "wizard":       "wand.and.stars",
        "xmag":         "magnifyingglass",
        "bookmark":     "bookmark",

        // Mindolph emoticon names (subset)
        "star":         "star.fill",
        "heart":        "heart.fill",
        "warning":      "exclamationmark.triangle.fill",
        "bomb":         "burst.fill",
        "bug":          "ant.fill",
        "lightning":    "bolt.fill",
        "rocket":       "paperplane.fill",
        "trophy":       "trophy.fill",
        "fire":         "flame.fill",
        "key":          "key.fill",
        "lock":         "lock.fill",
        "unlock":       "lock.open",
        "cloud":        "cloud.fill",
        "sun":          "sun.max.fill",
        "moon":         "moon.fill",
        "snowflake":    "snowflake",
        "pin":          "pin.fill",
        "tag":          "tag.fill",
        "book":         "book",
        "video":        "video.fill",
        "music":        "music.note",
        "camera":       "camera.fill",
        "phone":        "phone.fill",
        "email":        "envelope",
        "globe":        "globe",
        "house":        "house.fill",
        "car":          "car.fill",
        "plane":        "airplane",
        "gift":         "gift.fill",
        "money":        "dollarsign.circle.fill",
        "balance":      "scalemass",
        "battery":      "battery.100",
        "anchor":       "ferry",   // SF Symbols has no "anchor"; ferry is the nearest nautical glyph

        "apple":        "applelogo",
        "android":      "platter.2.filled.iphone",
    ]
}
