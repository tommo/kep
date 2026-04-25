import AppKit

/// Per-topic text alignment override stored in `TopicAttribute.textAlign`.
/// Lives in MindoMindMap (depends on AppKit's NSTextAlignment) so the
/// drawing path can map straight from a topic attribute to NSAlignment
/// without a second translation step.
public enum TopicTextAlign: String {
    case left, center, right

    public var nsAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }

    /// Parse the topic attribute. Unknown / nil values map to `.center` so
    /// the drawing default matches pre-feature behaviour.
    public static func from(attribute raw: String?) -> TopicTextAlign {
        guard let raw, let parsed = TopicTextAlign(rawValue: raw) else {
            return .center
        }
        return parsed
    }
}
