import Foundation

/// Temperature presets for the AI generation sheet — javamind parity with
/// `Temperature` (AiInputPane). The value is sent verbatim to the provider as
/// the sampling temperature; the label communicates the trade-off to the user.
public enum AITemperature: String, CaseIterable, Identifiable, Sendable {
    case deterministic
    case precise
    case balanced
    case flexible
    case creative

    public var id: String { rawValue }

    public var value: Float {
        switch self {
        case .deterministic: return 0.01
        case .precise:       return 0.25
        case .balanced:      return 0.5
        case .flexible:      return 0.75
        case .creative:      return 1.0
        }
    }

    public var label: String {
        switch self {
        case .deterministic: return "Deterministic"
        case .precise:       return "Precise"
        case .balanced:      return "Balanced"
        case .flexible:      return "Flexible"
        case .creative:      return "Creative"
        }
    }

    /// Default preset for a fresh sheet.
    public static let `default`: AITemperature = .balanced
}

/// Output-language choices for the AI generation sheet — javamind parity with
/// `cbLanguage`. `nil`/Auto leaves the prompt untouched; any other choice
/// appends a "respond in <language>" directive (kep's providers don't read
/// `LLMInput.outputLanguage`, so the instruction must live in the prompt).
public struct AIOutputLanguage: Identifiable, Hashable, Sendable {
    /// Stable id; empty string is the Auto sentinel.
    public let id: String
    /// Menu label.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    /// True for the "Auto" sentinel (no language directive).
    public var isAuto: Bool { id.isEmpty }

    public static let auto = AIOutputLanguage(id: "", name: "Auto")

    /// Auto first, then a spread of common languages (javamind ships 19; this
    /// is the high-frequency subset, extendable later).
    public static let all: [AIOutputLanguage] = [
        .auto,
        AIOutputLanguage(id: "en", name: "English"),
        AIOutputLanguage(id: "zh-Hans", name: "Simplified Chinese"),
        AIOutputLanguage(id: "zh-Hant", name: "Traditional Chinese"),
        AIOutputLanguage(id: "es", name: "Spanish"),
        AIOutputLanguage(id: "fr", name: "French"),
        AIOutputLanguage(id: "de", name: "German"),
        AIOutputLanguage(id: "ja", name: "Japanese"),
        AIOutputLanguage(id: "ko", name: "Korean"),
        AIOutputLanguage(id: "pt", name: "Portuguese"),
        AIOutputLanguage(id: "ru", name: "Russian"),
        AIOutputLanguage(id: "it", name: "Italian"),
        AIOutputLanguage(id: "ar", name: "Arabic"),
        AIOutputLanguage(id: "hi", name: "Hindi"),
    ]

    public static func by(id: String) -> AIOutputLanguage {
        all.first { $0.id == id } ?? .auto
    }

    /// Append a language directive to `prompt` unless this is Auto. Pure so it
    /// can be unit-tested without the sheet.
    public func applied(to prompt: String) -> String {
        guard !isAuto else { return prompt }
        return "\(prompt)\n\nRespond in \(name)."
    }
}
