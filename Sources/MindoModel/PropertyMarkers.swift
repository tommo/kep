import Foundation

/// A visual marker derived from a topic's well-known typed properties — the
/// spatial payoff of the keystone (#200): see priority / done / tags directly
/// on the node. Pure (no AppKit): carries a role + SF Symbol name; the canvas
/// resolves the role to a tint at draw time. See [[project_typed_properties]].
public struct PropertyMarker: Equatable {
    public enum Role: Equatable {
        case priority(Int)   // clamped 1...5
        case doneTrue
        case doneFalse
        case tags(Int)       // count (>= 1)
    }
    public let role: Role

    public init(role: Role) { self.role = role }

    /// The SF Symbol the canvas should render for this marker.
    public var symbolName: String {
        switch role {
        case .priority:  return "flag.fill"
        case .doneTrue:  return "checkmark.circle.fill"
        case .doneFalse: return "circle"
        case .tags:      return "tag.fill"
        }
    }
}

/// Maps a topic's well-known properties to the marker row drawn on its node.
/// Well-known keys (Phase 5): `priority` (number 1…5), `done` (checkbox),
/// `tags` (list). Only properties that parse to the expected type produce a
/// marker; a `priority` stored as text, say, simply renders nothing. Order is
/// stable: priority → done → tags.
public enum PropertyMarkers {

    public static let priorityKey = "priority"
    public static let doneKey = "done"
    public static let tagsKey = "tags"

    public static func markerRow(for topic: Topic) -> [PropertyMarker] {
        var out: [PropertyMarker] = []
        if case .number(let n)? = topic.property(priorityKey) {
            out.append(PropertyMarker(role: .priority(clampPriority(n))))
        }
        if case .checkbox(let done)? = topic.property(doneKey) {
            out.append(PropertyMarker(role: done ? .doneTrue : .doneFalse))
        }
        if case .list(let items)? = topic.property(tagsKey), !items.isEmpty {
            out.append(PropertyMarker(role: .tags(items.count)))
        }
        return out
    }

    /// Clamp an arbitrary numeric priority to the 1…5 band the markers model.
    static func clampPriority(_ n: Double) -> Int {
        max(1, min(5, Int(n.rounded())))
    }
}
