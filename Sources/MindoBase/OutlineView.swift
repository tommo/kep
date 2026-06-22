import SwiftUI

/// Sidebar list rendering of an `[OutlineItem]`. Indents by `depth` and emits
/// a tap on selection. Lightweight: just a SwiftUI `List`; tree disclosure
/// stays out of the way since the indentation already shows hierarchy.
public struct OutlinePanel: View {
    public let items: [OutlineItem]
    /// The `target` of the row to show as selected — driven by the editor's
    /// own selection (e.g. the mind-map canvas) so the outline highlight stays
    /// in sync with the graph. `nil` = no external selection.
    public var selectedTarget: String?
    public let onSelect: (OutlineItem) -> Void
    @State private var selection: OutlineItem.ID?
    @State private var filter: String = ""
    /// True while pushing the external `selectedTarget` into `selection`, so the
    /// selection `onChange` doesn't echo it back as a navigation request.
    @State private var syncing = false

    public init(items: [OutlineItem], selectedTarget: String? = nil, onSelect: @escaping (OutlineItem) -> Void) {
        self.items = items
        self.selectedTarget = selectedTarget
        self.onSelect = onSelect
    }

    /// Map the external `selectedTarget` to the (per-render, UUID) row id so the
    /// List highlights it. Recomputed whenever the target or the items change
    /// (the ids are regenerated each time the outline is rebuilt).
    private func syncSelectionFromTarget() {
        syncing = true
        selection = items.first { $0.target == selectedTarget }?.id
        DispatchQueue.main.async { syncing = false }
    }

    public var body: some View {
        if items.isEmpty {
            Text("No outline")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                // Filter bar — case-insensitive substring match against
                // item titles. Empty string passes everything through.
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Filter", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !filter.isEmpty {
                        Button { filter = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                Divider()
                List(filteredItems, selection: $selection) { item in
                    HStack(spacing: 4) {
                        if item.depth > 1 {
                            Spacer().frame(width: CGFloat((item.depth - 1) * 12))
                        }
                        Image(systemName: icon(for: item.depth))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        Text(item.title)
                            .font(.system(size: 13))   // match mindmap node text size
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if !item.markers.isEmpty {
                            Spacer(minLength: 4)
                            ForEach(Array(item.markers.enumerated()), id: \.offset) { _, marker in
                                Image(systemName: marker.symbolName)
                                    .font(.system(size: 9))
                                    .foregroundStyle(color(for: marker.tint))
                            }
                        }
                    }
                    .tag(item.id)
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 20)
                // Navigate on real selection changes (not the programmatic sync)
                // — drives off List selection so the row shows the normal arrow
                // cursor, not the link/hand cursor an onTapGesture triggers.
                .onChange(of: selection) { _, new in
                    guard !syncing, let id = new,
                          let item = items.first(where: { $0.id == id }) else { return }
                    onSelect(item)
                }
                .onAppear { syncSelectionFromTarget() }
                .onChange(of: selectedTarget) { _, _ in syncSelectionFromTarget() }
                .onChange(of: items) { _, _ in syncSelectionFromTarget() }
            }
        }
    }

    private var filteredItems: [OutlineItem] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Tint for an outline marker — mirrors the canvas marker colors so the
    /// outline reads consistently with the graph.
    private func color(for tint: OutlineMarker.Tint) -> Color {
        switch tint {
        case .priority(let p):
            switch p {
            case 1: return .red
            case 2: return .orange
            case 3: return .yellow
            case 4: return .blue
            default: return .gray
            }
        case .done:    return .green
        case .accent:  return .blue
        case .todo, .neutral: return .secondary
        }
    }

    private func icon(for depth: Int) -> String {
        switch depth {
        case 1: return "circle.fill"
        case 2: return "circle"
        case 3: return "smallcircle.filled.circle"
        default: return "smallcircle.circle"
        }
    }
}
