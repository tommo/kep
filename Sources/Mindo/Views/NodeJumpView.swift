import SwiftUI
import MindoBase
import MindoCore

/// "Go to Node" palette (⌘P): fuzzy-search the active mind map's topics and
/// jump to the chosen one. Mirrors `QuickSwitcherView` — chrome-light modal,
/// type to filter, arrows to move, Return to jump, Esc to dismiss.
struct NodeJumpView: View {
    let onSelect: (String) -> Void   // outline target of the chosen node
    let onClose: () -> Void

    @State private var model: NodeJumpModel
    @State private var query: String = ""
    @State private var selection: Int = 0
    @FocusState private var fieldFocused: Bool

    init(items: [OutlineItem], onSelect: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onClose = onClose
        _model = State(initialValue: NodeJumpModel(items: items))
    }

    private var ranked: [(item: OutlineItem, result: FuzzyMatch.Result)] { model.results }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.to.line")
                    .foregroundStyle(.secondary)
                TextField(L("nodejump.placeholder"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($fieldFocused)
                    .onChange(of: query) { _, new in model.setQuery(new); selection = model.selection }
                    .onSubmit { jumpSelected() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if ranked.isEmpty {
                Text(query.isEmpty ? L("nodejump.empty.prompt") : L("nodejump.empty.nomatch"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(ranked.enumerated()), id: \.element.item.id) { idx, entry in
                                NodeJumpRow(item: entry.item,
                                            matched: entry.result.matchedIndices,
                                            selected: idx == selection)
                                    .id(idx)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.select(at: idx); selection = model.selection; jumpSelected() }
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

    private func move(_ delta: Int) {
        model.move(delta)
        selection = model.selection
    }

    private func jumpSelected() {
        guard let item = model.selectedItem else { return }
        onSelect(item.target)
        onClose()
    }
}

/// A single node result row — the topic title with matched characters
/// emphasised, indented by its outline depth so the tree shape reads.
private struct NodeJumpRow: View {
    let item: OutlineItem
    let matched: [Int]
    let selected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.depth == 0 ? "smallcircle.filled.circle" : "circle")
                .font(.system(size: 7))
                .foregroundStyle(selected ? Color.white : Color.accentColor)
                .frame(width: 14)
            highlightedTitle
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(min(item.depth, 8)) * 12)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(selected ? Color.white : Color.primary)
    }

    private var highlightedTitle: Text {
        let chars = Array(item.title)
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
