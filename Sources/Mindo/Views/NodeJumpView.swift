import SwiftUI
import MindoBase
import MindoCore

/// "Go to Node" palette (⌘P): fuzzy-search the active mind map's topics and
/// jump to the chosen one. Chrome-light modal — type to filter, arrows to
/// move, Return to jump, Esc to dismiss.
///
/// The query is a `@Binding` owned by `AppSession`, NOT local `@State`. A
/// SwiftUI re-render can re-create this modal (the enclosing App body rebuilds
/// `session.outlineItems` — a computed property handing back fresh array
/// identities — on every pass), and a re-created view resets its own `@State`.
/// That silently zeroed a locally-stored query while the AppKit field editor
/// kept the visible glyphs, so `ranked` re-ran with an empty query and showed
/// every node unfiltered. Session-owned query survives the re-create. The item
/// set is snapshotted into `@State` so its churning identity can't thrash the
/// list either.
struct NodeJumpView: View {
    @Binding var query: String
    let onSelect: (String) -> Void   // outline target of the chosen node
    let onClose: () -> Void

    @State private var items: [OutlineItem]
    @State private var selection: Int = 0
    @FocusState private var fieldFocused: Bool

    init(items: [OutlineItem], query: Binding<String>,
         onSelect: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        _items = State(initialValue: items)
        _query = query
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
                                NodeJumpRow(item: entry.item,
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

/// A single node result row, two lines like the file switcher: the node title
/// (prominent, with matched chars bold) over its dim breadcrumb. Matching is
/// title-only, so `matched` indexes into the title; the breadcrumb is context.
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
                highlight(item.title, hits: matched)   // matching is on the title
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
                result = result + piece.fontWeight(.bold)
                    .foregroundColor(selected ? .white : .accentColor)
            } else {
                result = result + piece
            }
        }
        return result
    }
}
