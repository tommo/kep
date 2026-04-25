import SwiftUI

/// Sidebar list rendering of an `[OutlineItem]`. Indents by `depth` and emits
/// a tap on selection. Lightweight: just a SwiftUI `List`; tree disclosure
/// stays out of the way since the indentation already shows hierarchy.
public struct OutlinePanel: View {
    public let items: [OutlineItem]
    public let onSelect: (OutlineItem) -> Void
    @State private var selection: OutlineItem.ID?

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
            List(items, selection: $selection) { item in
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

    private func icon(for depth: Int) -> String {
        switch depth {
        case 1: return "circle.fill"
        case 2: return "circle"
        case 3: return "smallcircle.filled.circle"
        default: return "smallcircle.circle"
        }
    }
}
