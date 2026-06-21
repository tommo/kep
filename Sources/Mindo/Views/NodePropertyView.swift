import SwiftUI
import MindoModel

/// One typed property of the selected node, as an Equatable/Identifiable
/// snapshot for the inspector list. Identity is the key so SwiftUI keeps a
/// row's editor across value edits.
struct NodePropertyRow: Equatable, Identifiable {
    var key: String
    var value: PropertyValue
    var id: String { key }
}

/// SF Symbol + accessibility name for a property type, so each row advertises
/// the inferred kind.
private extension PropertyType {
    var symbolName: String {
        switch self {
        case .text:     return "textformat"
        case .number:   return "number"
        case .date:     return "calendar"
        case .checkbox: return "checkmark.square"
        case .list:     return "list.bullet"
        case .topicRef: return "arrow.uturn.right.circle"
        }
    }
}

/// The inspector's Properties panel — the visible consumer of the typed-node-
/// property model (keystone #200). Lists the selected node's user properties
/// with type-appropriate editing (checkbox → Toggle; number → field + Stepper;
/// date → DatePicker; text/list/topicRef → a field whose committed value is
/// re-inferred through PropertyCodec/Inference), plus add / remove. Built-in/
/// extra attributes never appear (reserved keys).
struct NodePropertiesView: View {
    @Binding var session: AppSession
    let properties: [NodePropertyRow]

    @State private var draftKey = ""
    @State private var draftValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if properties.isEmpty {
                Text(L("inspector.properties.empty"))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
            } else {
                ForEach(properties) { row in
                    NodePropertyRowView(
                        row: row,
                        onCommit: { session.setSelectedNodeProperty(row.key, $0) },
                        onDelete: { session.removeSelectedNodeProperty(row.key) }
                    )
                    .id(row.key)
                }
            }
            Divider().padding(.vertical, 2)
            Menu {
                ForEach(SupertagCatalog.all) { tag in
                    Button(tag.name) { session.applySupertag(named: tag.name) }
                }
            } label: {
                Label(L("inspector.properties.apply_template"), systemImage: "tag.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .padding(.horizontal, 8)
            HStack(spacing: 6) {
                TextField(L("inspector.properties.name"), text: $draftKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 110)
                TextField(L("inspector.properties.value"), text: $draftValue)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDraft)
                Button { addDraft() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .disabled(draftKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help(L("inspector.properties.add"))
            }
            .padding(.horizontal, 8)
        }
        .padding(.vertical, 4)
    }

    private func addDraft() {
        let key = draftKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        session.addSelectedNodeProperty(key: key, rawValue: draftValue)
        draftKey = ""; draftValue = ""
    }
}

/// One editable property row. Holds a local draft for text-style values so
/// typing doesn't write the model (and churn the snapshot) on every keystroke —
/// it commits on Return / focus loss. Checkbox commits immediately.
private struct NodePropertyRowView: View {
    let row: NodePropertyRow
    let onCommit: (PropertyValue) -> Void
    let onDelete: () -> Void

    @State private var draft = ""
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: row.value.kind.symbolName)
                .font(.caption2).foregroundStyle(.secondary).frame(width: 14)
            Text(row.key).font(.caption.weight(.medium)).lineLimit(1)
            Spacer(minLength: 6)
            editor
            Button { onDelete() } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help(L("inspector.properties.remove"))
        }
        .padding(.horizontal, 8)
        .onAppear { if !loaded { draft = PropertyCodec.encode(row.value); loaded = true } }
    }

    @ViewBuilder private var editor: some View {
        switch row.value {
        case .checkbox(let on):
            Toggle("", isOn: Binding(get: { on }, set: { onCommit(.checkbox($0)) }))
                .labelsHidden()
        case .number(let n):
            HStack(spacing: 2) {
                TextField("", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 64)
                    .multilineTextAlignment(.trailing)
                    .onSubmit { onCommit(PropertyInference.infer(draft)) }
                Stepper("", value: Binding(
                    get: { Double(draft) ?? n },
                    set: { v in draft = PropertyCodec.encode(.number(v)); onCommit(.number(v)) }
                ), step: 1)
                .labelsHidden()
            }
        case .date(let d):
            // Edit/display in UTC so a date-only value round-trips to UTC
            // midnight (matching PropertyCodec) with no off-by-one in local TZs.
            DatePicker("", selection: Binding(
                get: { d },
                set: { picked in onCommit(.date(Self.utcStartOfDay(picked))) }
            ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                .environment(\.timeZone, NodePropertyRowView.utc)
        default:
            TextField("", text: $draft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 130)
                .multilineTextAlignment(.trailing)
                .onSubmit { onCommit(PropertyInference.infer(draft)) }
        }
    }

    private static let utc = TimeZone(identifier: "UTC")!

    /// Normalize a picked instant to UTC midnight of its UTC calendar day, so the
    /// committed value encodes as a clean date-only string.
    private static func utcStartOfDay(_ date: Date) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return cal.startOfDay(for: date)
    }
}

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
