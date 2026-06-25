import AppKit

/// Helper behind the topic color context-menu items. Replaces the old
/// "type a #RRGGBB string" NSAlert text field with a native `NSColorWell`
/// accessory — clicking it opens the standard macOS color picker, so the
/// user never has to know hex. The OK/Cancel alert frame is kept so the
/// change is still a single, cancellable, undoable edit.
enum MindMapColorPicker {

    /// The color the well should start on: the topic's current color when it
    /// parses, otherwise `fallback`. Pure so the seeding is unit-testable
    /// without showing any UI.
    static func seedColor(currentAttribute: String?, fallback: NSColor) -> NSColor {
        MindMapColor.parse(currentAttribute) ?? fallback
    }

    /// Outcome of running the picker, mapped from the alert buttons.
    enum Result: Equatable {
        case cancelled
        case clear              // user hit "Clear"
        case pick(NSColor)      // user hit OK with a chosen color
    }

    /// Translate the alert's modal response into a `Result`. Split out so
    /// the button→result mapping is testable independent of NSAlert/runModal.
    /// `first` = OK, `second` = Clear, anything else = Cancel.
    static func result(for response: NSApplication.ModalResponse, chosen: NSColor) -> Result {
        switch response {
        case .alertFirstButtonReturn:  return .pick(chosen)
        case .alertSecondButtonReturn: return .clear
        default:                       return .cancelled
        }
    }
}
