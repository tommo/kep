import Foundation

/// A named set of typed properties — a "supertag" / schema template (the last
/// piece of keystone #200). Applying one stamps its fields onto a topic so a
/// node instantly gains a consistent, typed shape (and the matching canvas
/// markers). Pure model — no Topic/AppKit coupling beyond `apply(to:)`.
/// See [[project_typed_properties]].
public struct Supertag: Equatable, Sendable, Identifiable {

    /// One field of a supertag: a property key and the typed default value
    /// stamped when the key is absent. A concrete default (not just a type) means
    /// the value survives inference and renders its marker immediately.
    public struct Field: Equatable, Sendable {
        public let key: String
        public let defaultValue: PropertyValue
        public init(key: String, defaultValue: PropertyValue) {
            self.key = key
            self.defaultValue = defaultValue
        }
    }

    public let name: String
    public let fields: [Field]
    public var id: String { name }

    public init(name: String, fields: [Field]) {
        self.name = name
        self.fields = fields
    }

    /// Keys this supertag would add to `topic` — those not already present.
    public func missingKeys(in topic: Topic) -> [String] {
        fields.filter { topic.property($0.key) == nil }.map(\.key)
    }

    /// Non-destructively stamp this supertag's fields onto `topic`: a field is
    /// set to its default only when the key is absent (an existing value is never
    /// clobbered). Returns the keys that were added so the caller can group undo
    /// / report what changed.
    @discardableResult
    public func apply(to topic: Topic) -> [String] {
        var added: [String] = []
        for field in fields where topic.property(field.key) == nil {
            topic.setProperty(field.key, field.defaultValue)
            added.append(field.key)
        }
        return added
    }
}

/// The built-in supertag catalog. Each field carries a concrete typed default so
/// applying a template lights up the matching canvas markers at once. A later
/// phase makes these Lua-definable (user/vault supertags); this is the seed set.
public enum SupertagCatalog {

    public static let all: [Supertag] = [
        Supertag(name: "Task", fields: [
            .init(key: PropertyMarkers.priorityKey, defaultValue: .number(3)),
            .init(key: PropertyMarkers.doneKey, defaultValue: .checkbox(false)),
        ]),
        Supertag(name: "Tracked", fields: [
            .init(key: PropertyMarkers.progressKey, defaultValue: .number(0)),
            .init(key: PropertyMarkers.doneKey, defaultValue: .checkbox(false)),
        ]),
        Supertag(name: "Note", fields: [
            .init(key: PropertyMarkers.tagsKey, defaultValue: .list([])),
        ]),
    ]

    /// Case-insensitive lookup by name.
    public static func named(_ name: String) -> Supertag? {
        all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}
