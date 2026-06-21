import AppKit

/// General mindo styling rule: **selection / cursor emphasis degrades when its
/// view is not focused.** Like a native `NSTableView` whose blue selection
/// greys out the moment it stops being the key window's first responder, any
/// mindo surface that draws its own selection (the mind-map canvas, custom
/// grids, etc.) should dim that emphasis when focus moves elsewhere — so the
/// user can always tell, at a glance, which pane their keyboard is driving.
///
/// Use `FocusState.of(view)` to read the state and `degraded(_:focused:)` to
/// fade a highlight colour. Keep the emphasis (line width, halo) the same; only
/// the colour's strength changes, so the selection stays legible but clearly
/// secondary.
public enum FocusStyle {
    /// Multiplier applied to a selection colour's alpha when its view is
    /// unfocused. ~0.4 reads as "still visible, clearly not active".
    public static let unfocusedAlpha: CGFloat = 0.4

    /// Fade `color` for an unfocused selection. No-op when `focused`.
    public static func degraded(_ color: NSColor, focused: Bool) -> NSColor {
        guard !focused else { return color }
        return color.withAlphaComponent(color.alphaComponent * unfocusedAlpha)
    }

    /// Whether `view` currently owns keyboard focus: its window is key AND the
    /// first responder is the view itself or a descendant of it. The descendant
    /// case keeps a selection "focused" while an inline field editor (a child
    /// of the view) is active — editing a node is still focus, not a focus loss.
    /// A selection in a background window is as "unfocused" as one whose view
    /// lost first responder within the key window.
    public static func isFocused(_ view: NSView) -> Bool {
        guard let window = view.window, window.isKeyWindow else { return false }
        guard let responder = window.firstResponder else { return false }
        if responder === view { return true }
        return (responder as? NSView)?.isDescendant(of: view) ?? false
    }
}
