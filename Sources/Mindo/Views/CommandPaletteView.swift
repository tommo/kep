import SwiftUI
import MindoCore

/// One palette entry: the pure `AppCommand` (id/title/enabled — what the
/// model ranks) paired with the closure to run when it's chosen. The
/// closure stays in the UI layer so `CommandPaletteModel` remains testable.
struct PaletteCommand {
    let command: AppCommand
    let run: () -> Void
}

/// Obsidian-style ⌘⇧P command palette: fuzzy-search every global action by
/// name, Return to run it. Mirrors `QuickSwitcherView` (chrome-light modal,
/// arrow-key nav, Esc to close) so the two read as one family.
struct CommandPaletteView: View {
    let commands: [PaletteCommand]
    let onClose: () -> Void

    @State private var model: CommandPaletteModel
    @State private var query: String = ""
    @State private var selection: Int = 0
    @FocusState private var fieldFocused: Bool

    /// Closures keyed by command id so a chosen `AppCommand` can find its run.
    private let actions: [String: () -> Void]

    init(commands: [PaletteCommand], onClose: @escaping () -> Void) {
        self.commands = commands
        self.onClose = onClose
        self.actions = Dictionary(uniqueKeysWithValues: commands.map { ($0.command.id, $0.run) })
        _model = State(initialValue: CommandPaletteModel(commands: commands.map { $0.command }))
    }

    private var ranked: [(item: AppCommand, result: FuzzyMatch.Result)] { model.results }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .foregroundStyle(.secondary)
                TextField(L("palette.placeholder"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($fieldFocused)
                    .onChange(of: query) { _, new in model.setQuery(new); selection = model.selection }
                    .onSubmit { runSelected() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if ranked.isEmpty {
                Text(query.isEmpty ? L("palette.empty.prompt") : L("palette.empty.nomatch"))
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            // No `.id(idx)` — it overrides the ForEach item-id
                            // identity, so a shrinking result set reuses the
                            // idx-0 row and shows stale content.
                            ForEach(Array(ranked.enumerated()), id: \.element.item.id) { idx, entry in
                                CommandRow(
                                    command: entry.item,
                                    matched: entry.result.matchedIndices,
                                    selected: idx == selection
                                )
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    model.select(at: idx)
                                    selection = model.selection
                                    runSelected()
                                }
                            }
                        }
                        .padding(6)
                    }
                    .frame(height: 320)
                    .onChange(of: selection) { _, new in
                        guard ranked.indices.contains(new) else { return }
                        withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(ranked[new].item.id, anchor: .center) }
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

    private func runSelected() {
        guard let cmd = model.selectedCommand else { return }
        onClose()
        actions[cmd.id]?()
    }
}

/// A single palette row: command name (matched chars emphasised), optional
/// category on the right, plus a rendered shortcut. Disabled commands dim.
private struct CommandRow: View {
    let command: AppCommand
    let matched: [Int]
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            highlightedTitle
                .lineLimit(1)
            Spacer(minLength: 8)
            if let cat = command.category {
                Text(cat)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.7) : .secondary)
            }
            if let sc = command.shortcut {
                Text(sc)
                    .font(.caption.monospaced())
                    .foregroundStyle(selected ? Color.white.opacity(0.85) : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .opacity(command.isEnabled ? 1 : 0.4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(selected ? Color.white : Color.primary)
    }

    private var highlightedTitle: Text {
        let chars = Array(command.title)
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
