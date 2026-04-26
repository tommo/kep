import SwiftUI

/// Sidebar list rendering of an `[OutlineItem]`. Indents by `depth` and emits
/// a tap on selection. Lightweight: just a SwiftUI `List`; tree disclosure
/// stays out of the way since the indentation already shows hierarchy.
public struct OutlinePanel: View {
    public let items: [OutlineItem]
    public let onSelect: (OutlineItem) -> Void
    @State private var selection: OutlineItem.ID?
    @State private var filter: String = ""

    public init(items: [OutlineItem], onSelect: @escaping (OutlineItem) -> Void) {
        self.items = items
        self.onSelect = onSelect
    }

    public var body: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No Outline",
                systemImage: "list.bullet.indent",
                description: Text("Add headings or topics to see them here.")
            )
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
                        Text(String(repeating: " ", count: max(0, (item.depth - 1) * 2)))
                        Image(systemName: icon(for: item.depth))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .tag(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(item) }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var filteredItems: [OutlineItem] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
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
