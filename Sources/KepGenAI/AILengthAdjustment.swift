import Foundation

/// Post-generation "reframe" adjustment (javamind `AiReframePane` parity): after
/// a result is produced, re-run the same prompt asking for a shorter or longer
/// version. Pure so the prompt-building is unit-testable without a provider.
public enum AILengthAdjustment: String, CaseIterable, Hashable, Sendable {
    case shorter
    case longer

    /// The instruction appended to the original prompt on re-run.
    public var directive: String {
        switch self {
        case .shorter: return "Rewrite your previous response to be more concise and shorter, keeping the key points."
        case .longer:  return "Rewrite your previous response with more detail and explanation, staying on topic."
        }
    }

    public var label: String {
        switch self {
        case .shorter: return "Shorter"
        case .longer:  return "Longer"
        }
    }

    public var systemImage: String {
        switch self {
        case .shorter: return "arrow.down.right.and.arrow.up.left"
        case .longer:  return "arrow.up.left.and.arrow.down.right"
        }
    }

    /// The prompt to re-run: the original prompt followed by the length
    /// directive. Trailing whitespace on `base` is trimmed so the directive
    /// always lands on its own paragraph.
    public func applied(to base: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? directive : "\(trimmed)\n\n\(directive)"
    }
}
