import AppKit

/// Helpers for driving NSTextView's built-in find bar from a menu command.
///
/// `NSTextView.performFindPanelAction(_:)` decides *which* operation to run
/// (show / next / previous / replace…) by reading the **sender's `tag`**.
/// The old ⌘F path sent the action with a `nil` sender, whose tag is `0` —
/// not a valid `NSFindPanelAction` — so the find bar never appeared and
/// ⌘F silently did nothing in the markdown / plantuml / text editors even
/// though `usesFindBar` was set. Building a sender that carries the right
/// tag is the fix.
public enum TextFindBar {

    /// The find-bar operations we drive. Raw values mirror AppKit's
    /// `NSFindPanelAction` so `performFindPanelAction(_:)` dispatches
    /// correctly; `FindBarActionTests` guards them against SDK drift.
    public enum Action: Int {
        case showFindPanel = 1     // NSFindPanelAction.showFindPanel — opens the find bar
        case next          = 2
        case previous      = 3
        case replaceAll    = 4
        case replace       = 5
        case replaceAndFind = 6
    }

    /// A sender object carrying the `tag` that
    /// `performFindPanelAction(_:)` reads to choose the operation. Pass it
    /// as the `from:` of `NSApp.sendAction` so it routes to the first
    /// responder (the focused text view).
    public static func sender(for action: Action) -> NSMenuItem {
        let item = NSMenuItem()
        item.tag = action.rawValue
        return item
    }

    /// Show the find bar in the active text view via the responder chain.
    /// Returns whether an action target accepted it (mostly for tests /
    /// callers that want to know a responder handled it).
    @discardableResult
    public static func showFindBar() -> Bool {
        NSApp.sendAction(
            Selector(("performFindPanelAction:")),
            to: nil,
            from: sender(for: .showFindPanel))
    }
}
