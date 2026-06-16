import SwiftUI
import MindoBase
import MindoCore

/// "Go to Node" palette (⌘P): fuzzy-search the active mind map's topics by
/// title and jump to the chosen one. Uses the AppKit-backed PaletteSearchField
/// (reliable focus + edit propagation in a sheet); results are a pure function
/// of `query`, so the list always tracks the input.
struct NodeJumpView: View {
    let onSelect: (String) -> Void   // outline target of the chosen node
    let onClose: () -> Void

    @State private var items: [OutlineItem]
    @State private var query: String = ""
    @State private var selection: Int = 0

    init(items: [OutlineItem], onSelect: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        _items = State(initialValue: items)
        self.onSelect = onSelect
        self.onClose = onClose
    }

    private var ranked: [(item: OutlineItem, result: FuzzyMatch.Result)] {
        NodeJumpSearch.results(items, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.to.line").foregroundStyle(.secondary)
                PaletteSearchField(
                    text: $query,
                    placeholder: L("nodejump.placeholder"),
                    onMoveUp: { move(-1) },
                    onMoveDown: { move(1) },
                    onSubmit: { jumpSelected() },
                    onCancel: { onClose() }
                )
                .frame(height: 24)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            let results = ranked
            if results.isEmpty {
                Text(query.isEmpty ? L("nodejump.empty.prompt") : L("nodejump.empty.nomatch"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // Identity is the item's id (via ForEach). Do NOT add
                            // a positional `.id(idx)` here — it overrides that
                            // identity, so when results shrink SwiftUI reuses the
                            // idx-0 row and shows its stale content.
                            ForEach(Array(results.enumerated()), id: \.element.item.id) { idx, entry in
                                NodeJumpRow(item: entry.item,
                                            matched: entry.result.matchedIndices,
                                            selected: idx == clamped(results))
                                    .contentShape(Rectangle())
                                    .onTapGesture { selection = idx; jumpSelected() }
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: 320)
                    .onChange(of: selection) { _, new in
                        let r = ranked
                        guard r.indices.contains(new) else { return }
                        withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(r[new].item.id, anchor: .center) }
                    }
                }
            }
        }
        .frame(width: 560)
        .background(.regularMaterial)
    }

    private func clamped(_ results: [(item: OutlineItem, result: FuzzyMatch.Result)]) -> Int {
        min(max(0, selection), max(0, results.count - 1))
    }

    private func move(_ delta: Int) {
        let count = ranked.count
        guard count > 0 else { selection = 0; return }
        selection = min(max(0, clamped(ranked) + delta), count - 1)
    }

    private func jumpSelected() {
        let results = ranked
        let idx = clamped(results)
        guard results.indices.contains(idx) else { return }
        onSelect(results[idx].item.target)
        onClose()
    }
}

/// A single node result row, two lines: the node title (prominent, matched
/// chars bold) over its dim breadcrumb. Matching is title-only, so `matched`
/// indexes into the title; the breadcrumb is context.
private struct NodeJumpRow: View {
    let item: OutlineItem
    let matched: [Int]
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(selected ? Color.white : Color.accentColor.opacity(0.7))
                .frame(width: 10)
            VStack(alignment: .leading, spacing: 1) {
                highlight(item.title, hits: matched)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !item.breadcrumb.isEmpty {
                    Text(item.breadcrumb)
                        .font(.caption2)
                        .foregroundColor(selected ? Color.white.opacity(0.75) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(selected ? Color.white : Color.primary)
    }

    private func highlight(_ string: String, hits rawHits: [Int]) -> Text {
        let chars = Array(string)
        let hits = Set(rawHits)
        var result = Text("")
        for (i, ch) in chars.enumerated() {
            let piece = Text(String(ch))
            if hits.contains(i) {
                result = result + piece.fontWeight(.bold).foregroundColor(selected ? .white : .accentColor)
            } else {
                result = result + piece
            }
        }
        return result
    }
}
