import SwiftUI
import MindoCore

/// Obsidian-style ⌘O quick switcher: type a few characters, fuzzy-match
/// against every file in the open workspaces, Return to open. Arrow keys
/// move the highlight; Esc dismisses. Deliberately chrome-light (no window
/// title bar, no toolbar) so it reads like Obsidian's command modal rather
/// than a native macOS open panel.
struct QuickSwitcherView: View {
    let onOpen: (URL) -> Void
    let onClose: () -> Void

    @State private var model: QuickSwitcherModel
    @State private var query: String = ""
    @State private var selection: Int = 0
    @FocusState private var fieldFocused: Bool

    init(files: [WorkspaceFile], onOpen: @escaping (URL) -> Void, onClose: @escaping () -> Void) {
        self.onOpen = onOpen
        self.onClose = onClose
        _model = State(initialValue: QuickSwitcherModel(files: files))
    }

    private var ranked: [(item: WorkspaceFile, result: FuzzyMatch.Result)] { model.results }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L("switcher.placeholder"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($fieldFocused)
                    .onChange(of: query) { _, new in model.setQuery(new); selection = model.selection }
                    .onSubmit { openSelected() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            // Results
            if ranked.isEmpty {
                VStack {
                    Text(query.isEmpty ? L("switcher.empty.prompt") : L("switcher.empty.nomatch"))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(ranked.enumerated()), id: \.element.item.id) { idx, entry in
                                ResultRow(
                                    file: entry.item,
                                    matched: entry.result.matchedIndices,
                                    selected: idx == selection
                                )
                                .id(idx)
                                .contentShape(Rectangle())
                                .onTapGesture { model.select(at: idx); selection = model.selection; openSelected() }
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
        // Keyboard nav handled at the container so it works regardless of
        // which subview holds focus.
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    private func move(_ delta: Int) {
        model.move(delta)
        selection = model.selection
    }

    private func openSelected() {
        guard let file = model.selectedFile else { return }
        onOpen(file.url)
        onClose()
    }
}

/// A single result row — file name (with matched characters emphasised)
/// over a dim workspace-relative path, plus a type glyph.
private struct ResultRow: View {
    let file: WorkspaceFile
    let matched: [Int]
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: file.url.sfSymbolForFile)
                .foregroundStyle(selected ? Color.white : Color.accentColor)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                highlightedPath
                    .lineLimit(1)
                    .truncationMode(.head)
                Text(file.workspaceName)
                    .font(.caption2)
                    .foregroundStyle(selected ? Color.white.opacity(0.75) : .secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor : Color.clear)
        )
        .foregroundStyle(selected ? Color.white : Color.primary)
    }

    /// Bold the fuzzy-matched characters of the relative path so the user
    /// sees why this row matched. `matched` holds indices into
    /// `relativePath` (the key fuzzy-ranked against).
    private var highlightedPath: Text {
        let chars = Array(file.relativePath)
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

private extension URL {
    /// SF Symbol for this file based on its classified type, falling back
    /// to a generic document glyph.
    var sfSymbolForFile: String {
        SupportedFileType.classify(url: self)?.sfSymbolName
            ?? SupportedFileType.unknownSymbolName
    }
}
