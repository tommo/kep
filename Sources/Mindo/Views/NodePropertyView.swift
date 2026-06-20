import SwiftUI
import MindoModel

/// Value snapshot of a mind-map node's properties, so the SwiftUI property
/// panel updates purely on selection change (Topic is a reference type SwiftUI
/// can't observe directly).
struct NodeProperties: Equatable {
    var title: String
    var depth: Int
    var childCount: Int
    var note: String?        // "🔒 Encrypted" when the note is locked
    var link: String?
    var file: String?
    var jumpTarget: String?  // title of the linked topic, if any
    var fillColor: String?
    var textColor: String?
    var borderColor: String?
    var side: String?        // "Left"/"Right", only meaningful for root's children

    /// Build from a topic, its outline `path` (for depth), and the owning map
    /// (to resolve a jump-link UID back to a title).
    static func from(topic: Topic, path: String, map: MindMap) -> NodeProperties {
        let depth = path.isEmpty ? 1 : path.split(separator: "/").count + 1
        var note: String?
        if let n = topic.extra(.note) as? ExtraNote {
            note = NoteEncryption.looksEncrypted(n.text) ? "🔒 Encrypted" : n.text
        }
        var jump: String?
        if let t = topic.extra(.topic) as? ExtraTopic, let dest = map.findTopic(uid: t.value) {
            jump = dest.text.isEmpty ? "(untitled)" : dest.text
        }
        var side: String?
        if depth == 2, let v = topic.attribute(TopicAttribute.leftSide) {
            side = (v == "true") ? "Left" : "Right"
        }
        return NodeProperties(
            title: topic.text.isEmpty ? "(untitled)" : topic.text,
            depth: depth,
            childCount: topic.children.count,
            note: note,
            link: (topic.extra(.link) as? ExtraLink)?.uri,
            file: (topic.extra(.file) as? ExtraFile)?.uri,
            jumpTarget: jump,
            fillColor: topic.attribute(TopicAttribute.fillColor),
            textColor: topic.attribute(TopicAttribute.textColor),
            borderColor: topic.attribute(TopicAttribute.borderColor),
            side: side)
    }
}
