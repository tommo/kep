import SwiftUI

/// Visual icon grid shown in an NSPopover when the user picks "Set Icon…"
/// on a topic — replaces the old free-text NSAlert where you had to know
/// the icon's name. Obsidian-style: click a glyph to apply, with a search
/// box to narrow the list and a Clear button to remove the current icon.
struct EmoticonPickerView: View {
    /// Currently-set emoticon name, highlighted in the grid.
    let current: String?
    /// nil = clear the icon; otherwise the chosen emoticon name.
    let onPick: (String?) -> Void

    @State private var query: String = ""

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 6), count: 7)

    private var items: [(name: String, symbol: String)] {
        let all = MindMapEmoticon.pickerItems
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { $0.name.contains(q) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.caption)
                TextField("Search icons…", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))

            ScrollView {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(items, id: \.name) { item in
                        Button {
                            onPick(item.name)
                        } label: {
                            Image(systemName: item.symbol)
                                .font(.system(size: 15))
                                .frame(width: 30, height: 30)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(item.name == current ? Color.accentColor.opacity(0.25) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(item.name)
                    }
                }
                .padding(2)
            }
            .frame(height: 180)

            Divider()
            HStack {
                Button("Clear", role: .destructive) { onPick(nil) }
                    .disabled(current == nil)
                Spacer()
                Text("\(items.count) icons").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: 290)
    }
}
