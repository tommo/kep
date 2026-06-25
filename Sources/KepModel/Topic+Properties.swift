import Foundation

/// Typed node properties projected over `Topic.attributes` — Phase 2 of the
/// keystone (#200). Properties are NOT a separate store: every value lives as a
/// plain string in `attributes`, so the existing `.mmd` `> ` serializer
/// round-trips them for free (back-compat). `PropertyValue`/`PropertyCodec` are
/// the typed *view*; this extension decides which attributes are user
/// properties and bridges them. See [[project_typed_properties]].
public extension Topic {

    /// Attribute keys the renderer / extras own — never surfaced or settable as
    /// user properties. Anything else in `attributes` is a user property.
    static let reservedAttributeKeys: Set<String> = [
        TopicAttribute.fillColor, TopicAttribute.textColor, TopicAttribute.borderColor,
        TopicAttribute.leftSide, TopicAttribute.collapsed, TopicAttribute.emoticon,
        TopicAttribute.image, TopicAttribute.edgeColor, TopicAttribute.edgeStyle,
        TopicAttribute.edgeWidth, TopicAttribute.textAlign,
        TopicAttribute.offsetX, TopicAttribute.offsetY,
        ExtraTopic.topicUidAttr, ExtraNote.attrEncrypted, ExtraNote.attrPasswordHint,
    ]

    /// True when `key` is a built-in/extra attribute rather than a user
    /// property. Covers the explicit reserved set plus the `mmd.` / `extras.`
    /// system namespaces, so future built-ins stay excluded automatically.
    static func isReservedAttributeKey(_ key: String) -> Bool {
        reservedAttributeKeys.contains(key) || key.hasPrefix("mmd.") || key.hasPrefix("extras.")
    }

    /// User-property attribute keys (everything not reserved), sorted for stable
    /// presentation.
    var propertyKeys: [String] {
        attributes.keys.filter { !Topic.isReservedAttributeKey($0) }.sorted()
    }

    /// The typed value of a user property, inferred from its stored string.
    /// nil when the key is absent or reserved.
    func property(_ key: String) -> PropertyValue? {
        guard !Topic.isReservedAttributeKey(key), let raw = attribute(key) else { return nil }
        return PropertyInference.infer(raw)
    }

    /// All user properties as typed values (inferred).
    var typedProperties: [String: PropertyValue] {
        var out: [String: PropertyValue] = [:]
        for key in propertyKeys {
            if let raw = attribute(key) { out[key] = PropertyInference.infer(raw) }
        }
        return out
    }

    /// Set (or, with nil, remove) a user property. Encodes through
    /// `PropertyCodec` so the on-disk string stays canonical. No-op when `key`
    /// is reserved — properties can't shadow built-in/extra attributes.
    func setProperty(_ key: String, _ value: PropertyValue?) {
        guard !Topic.isReservedAttributeKey(key) else { return }
        setAttribute(key, value.map(PropertyCodec.encode))
    }
}
