import Foundation

/// Polymorphic metadata attached to a `Topic`. Mirrors `Extra<T>` from the Java original.
public protocol Extra: AnyObject {
    var type: ExtraType { get }
    var value: String { get }
    var asString: String { get }
    var stringForSave: String { get }
    var isExportable: Bool { get }

    /// Side effects on a topic's serialized attributes when this extra is written.
    /// Most extras don't add any; `ExtraNote` adds encryption flags.
    func addAttributesForWrite(_ attrs: inout [String: String])
}

public extension Extra {
    var isExportable: Bool { true }
    func addAttributesForWrite(_ attrs: inout [String: String]) {}

    /// Serialized form used by `Topic.write`: `- TYPE\n<pre>escaped value</pre>\n`.
    func write(to out: inout String) {
        out.append("- \(type.rawName)\(MmdConstants.nextLine)")
        out.append(ModelUtils.makePreBlock(stringForSave))
    }
}

public enum ExtraType: String, CaseIterable {
    case file = "FILE"
    case link = "LINK"
    case note = "NOTE"
    case topic = "TOPIC"
    case unknown = "UNKNOWN"

    public var rawName: String { rawValue }

    public static func from(token: String) -> ExtraType? {
        return ExtraType(rawValue: token)
    }

    /// Pre-process `<pre>` body content the same way the Java side does.
    /// Returns nil if the value is invalid (e.g. URI fails to parse for FILE/LINK).
    public func preprocess(_ s: String) -> String? {
        switch self {
        case .file, .link:
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            // Java parses with URI.create; we accept any non-empty string and let a richer
            // URI type validate later. Empty values are rejected.
            return trimmed.isEmpty ? nil : trimmed
        case .topic:
            return s.trimmingCharacters(in: .whitespacesAndNewlines)
        case .note, .unknown:
            return s
        }
    }

    /// Build a concrete `Extra` from a parsed `<pre>` body and the topic's attributes.
    public func parseLoaded(value: String, attributes: [String: String]) -> any Extra {
        let preprocessed = ModelUtils.unescapeHtml(value)
        switch self {
        case .file:
            return ExtraFile(uri: preprocessed)
        case .link:
            return ExtraLink(uri: preprocessed)
        case .note:
            let encrypted = (attributes[ExtraNote.attrEncrypted].flatMap(Bool.init)) ?? false
            let hint = attributes[ExtraNote.attrPasswordHint]
            return ExtraNote(text: preprocessed, encrypted: encrypted, hint: hint)
        case .topic:
            return ExtraTopic(topicUID: preprocessed)
        case .unknown:
            return ExtraNote(text: preprocessed)
        }
    }
}

public final class ExtraNote: Extra {
    public static let attrEncrypted = "extras.note.encrypted"
    public static let attrPasswordHint = "extras.note.encrypted.hint"

    public let text: String
    public let encrypted: Bool
    public let hint: String?

    public init(text: String, encrypted: Bool = false, hint: String? = nil) {
        self.text = text
        self.encrypted = encrypted
        self.hint = hint
    }

    public var type: ExtraType { .note }
    public var value: String { text }
    public var asString: String { text }
    public var stringForSave: String { text }

    public func addAttributesForWrite(_ attrs: inout [String: String]) {
        if encrypted { attrs[Self.attrEncrypted] = "true" }
        if let hint = hint, !hint.isEmpty { attrs[Self.attrPasswordHint] = hint }
    }
}

public final class ExtraLink: Extra {
    public let uri: String
    public init(uri: String) { self.uri = uri }
    public var type: ExtraType { .link }
    public var value: String { uri }
    public var asString: String { uri }
    public var stringForSave: String { uri }
}

public final class ExtraFile: Extra {
    public let uri: String
    public init(uri: String) { self.uri = uri }
    public var type: ExtraType { .file }
    public var value: String { uri }
    public var asString: String { uri }
    public var stringForSave: String { uri }
}

public final class ExtraTopic: Extra {
    public static let topicUidAttr = "topicLinkUID"

    public let topicUID: String
    public init(topicUID: String) { self.topicUID = topicUID }
    public var type: ExtraType { .topic }
    public var value: String { topicUID }
    public var asString: String { topicUID }
    public var stringForSave: String { topicUID }
}
