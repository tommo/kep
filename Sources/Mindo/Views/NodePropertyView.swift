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

/// Compact read-only property panel for the selected mind-map node. Lives in
/// the inspector's lower split, below the outline.
struct NodePropertyView: View {
    let properties: NodeProperties?

    var body: some View {
        if let p = properties {
            Form {
                Section("Topic") {
                    row("Title", p.title)
                    row("Level", "\(p.depth)")
                    row("Children", "\(p.childCount)")
                    if let s = p.side { row("Side", s) }
                }
                if p.note != nil || p.link != nil || p.file != nil || p.jumpTarget != nil {
                    Section("Extras") {
                        if let n = p.note { row("Note", n) }
                        if let l = p.link { row("Link", l) }
                        if let f = p.file { row("File", f) }
                        if let j = p.jumpTarget { row("Jumps to", j) }
                    }
                }
                if p.fillColor != nil || p.textColor != nil || p.borderColor != nil {
                    Section("Colors") {
                        if let c = p.fillColor { colorRow("Fill", c) }
                        if let c = p.textColor { colorRow("Text", c) }
                        if let c = p.borderColor { colorRow("Border", c) }
                    }
                }
            }
            .formStyle(.grouped)
            .controlSize(.small)
            .font(.caption)
        } else {
            Text("No selection")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        LabeledContent {
            Text(value).lineLimit(2).truncationMode(.middle)
                .foregroundStyle(.secondary).textSelection(.enabled)
        } label: {
            Text(label)
        }
    }

    private func colorRow(_ label: String, _ hex: String) -> some View {
        LabeledContent {
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: hex) ?? .clear)
                    .frame(width: 12, height: 12)
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(.separator))
                Text(hex).foregroundStyle(.secondary).font(.caption2)
            }
        } label: {
            Text(label)
        }
    }
}

private extension Color {
    /// Parse `#RRGGBB` / `RRGGBB` into a Color, nil on bad input.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        self = Color(
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255)
    }
}
