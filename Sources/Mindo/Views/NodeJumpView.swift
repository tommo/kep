import SwiftUI
import MindoBase
import MindoCore

/// "Go to Node" palette (⌘P): fuzzy-search the active mind map's topics and
/// jump to the chosen one. Chrome-light modal — type to filter, arrows to
/// move, Return to jump, Esc to dismiss.
///
/// Results are computed PURELY from the `query` @State (not by mutating a
/// reference-type model), so SwiftUI always re-ranks as you type — mutating a
/// class held in @State doesn't reliably invalidate the body, which left the
/// list stale/empty while typing.
struct NodeJumpView: View {
    let items: [OutlineItem]
    let onSelect: (String) -> Void   // outline target of the chosen node
    let onClose: () -> Void

    @State private var query: String = ""
    @State private var selection: Int = 0
    @FocusState private var fieldFocused: Bool

    init(items: [OutlineItem], onSelect: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.items = items
        self.onSelect = onSelect
        self.onClose = onClose
    }

    private var ranked: [(item: OutlineItem, result: FuzzyMatch.Result)] {
        NodeJumpSearch.results(items, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.to.line")
                    .foregroundStyle(.secondary)
                TextField(L("nodejump.placeholder"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($fieldFocused)
                    .onChange(of: query) { _, _ in selection = 0 }
                    .onSubmit { jumpSelected() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

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
                            ForEach(Array(results.enumerated()), id: \.element.item.id) { idx, entry in
                                NodeJumpRow(path: NodeJumpSearch.pathKey(entry.item),
                                            depth: entry.item.depth,
                                            matched: entry.result.matchedIndices,
                                            selected: idx == clampedSelection(results))
                                    .id(idx)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selection = idx; jumpSelected() }
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: 320)
                    .onChange(of: selection) { _, new in
                        withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(new, anchor: .center) }
                    }
                }
            }
        }
        .frame(width: 560)
        .background(.regularMaterial)
        .onAppear { fieldFocused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func clampedSelection(_ results: [(item: OutlineItem, result: FuzzyMatch.Result)]) -> Int {
        min(max(0, selection), max(0, results.count - 1))
    }

    private func move(_ delta: Int) {
        let count = ranked.count
        guard count > 0 else { selection = 0; return }
        selection = min(max(0, selection + delta), count - 1)
    }

    private func jumpSelected() {
        let results = ranked
        let idx = clampedSelection(results)
        guard results.indices.contains(idx) else { return }
        onSelect(results[idx].item.target)
        onClose()
    }
}

/// A single node result row — the full breadcrumb path with matched characters
/// emphasised. Head-truncated so the leaf node (the bit you're jumping to)
/// stays visible when the path is long.
private struct NodeJumpRow: View {
    let path: String
    let depth: Int
    let matched: [Int]
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: depth <= 1 ? "smallcircle.filled.circle" : "circle")
                .font(.system(size: 7))
                .foregroundStyle(selected ? Color.white : Color.accentColor)
                .frame(width: 14)
            highlightedPath
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(selected ? Color.white : Color.primary)
    }

    private var highlightedPath: Text {
        let chars = Array(path)
        let hits = Set(matched)
        var result = Text("")
        for (i, ch) in chars.enumerated() {
            let piece = Text(String(ch))
            if hits.contains(i) {
                result = result + piece.fontWeight(.bold)
                    .foregroundColor(selected ? .white : .accentColor)
            } else {
                result = result + piece
            }
        }
        return result
    }
}
