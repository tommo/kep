import SwiftUI
import MindoBase
import MindoCore

/// "Go to Node" palette (⌘P): fuzzy-search the active mind map's topics and
/// jump to the chosen one.
///
/// Two things make this robust:
///  • `query` is a Binding into @Observable `AppSession`, NOT local @State.
///    The enclosing App body hands in a fresh `session.outlineItems` array each
///    pass, which can give this modal a new identity and reset its local
///    @State; a session-owned query survives that re-create (the field editor
///    keeps the glyphs, so a reset query was the "text present, list unfiltered"
///    symptom).
///  • `ranked` is a PURE function of `query` — no model mutated in `onChange`,
///    which reads last-cycle results during the render a keystroke triggers and
///    lags the list behind the input.
struct NodeJumpView: View {
    @Binding var query: String       // owned by AppSession — survives re-create
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
                                            selected: idx == clamped(results))
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

    private func clamped(_ results: [(item: OutlineItem, result: FuzzyMatch.Result)]) -> Int {
        min(max(0, selection), max(0, results.count - 1))
    }

    private func move(_ delta: Int) {
        let count = ranked.count
        guard count > 0 else { selection = 0; return }
        selection = min(max(0, selection + delta), count - 1)
    }

    private func jumpSelected() {
        let results = ranked
        let idx = clamped(results)
        guard results.indices.contains(idx) else { return }
        onSelect(results[idx].item.target)
        onClose()
    }
}

/// A single node result row, two lines like the file switcher: the node title
/// (prominent, matched chars bold) over its dim breadcrumb. Matching is
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
                result = result + piece.fontWeight(.bold)
                    .foregroundColor(selected ? .white : .accentColor)
            } else {
                result = result + piece
            }
        }
        return result
    }
}
