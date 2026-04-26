import SwiftUI
import AppKit
import MindoModel

/// In-document Find / Replace bar for the mindmap canvas. Wraps a
/// MindMapView weak reference; query text drives findMatches → caller
/// flips through results, can replace one or all. Mirrors the shape of
/// mindolph's MindMapEditor.replaceAll() at the UX level.
@MainActor
public struct MindMapFindBar: View {
    public let view: MindMapView
    public var onClose: () -> Void

    @State private var query: String = ""
    @State private var replacement: String = ""
    @State private var caseSensitive: Bool = false
    @State private var matches: [MindMapElement] = []
    @State private var index: Int = 0

    public init(view: MindMapView, onClose: @escaping () -> Void = {}) {
        self.view = view
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find topic…", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 180)
                .onSubmit { gotoNext() }
                .onChange(of: query) { _, _ in refreshMatches() }
            Toggle("Aa", isOn: $caseSensitive)
                .toggleStyle(.button)
                .help("Case-sensitive")
                .onChange(of: caseSensitive) { _, _ in refreshMatches() }
            Text(countLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 56, alignment: .trailing)
            Button { gotoPrevious() } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.bordered)
                .disabled(matches.isEmpty)
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Button { gotoNext() } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.bordered)
                .disabled(matches.isEmpty)
                .keyboardShortcut("g", modifiers: .command)
            Divider().frame(height: 16)
            TextField("Replace with…", text: $replacement)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 140)
            Button("Replace") { replaceCurrent() }
                .buttonStyle(.bordered)
                .disabled(matches.isEmpty)
                .help("Replace this match and advance to the next")
            Button("Replace All") { replaceAll() }
                .buttonStyle(.bordered)
                .disabled(matches.isEmpty)
            Spacer()
            Button { onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }

    private var countLabel: String {
        if matches.isEmpty { return query.isEmpty ? "" : "0 / 0" }
        return "\(index + 1) / \(matches.count)"
    }

    private func refreshMatches() {
        matches = view.findMatches(query: query, caseSensitive: caseSensitive)
        index = 0
        select(matchIndex: 0)
    }

    private func gotoNext() {
        guard !matches.isEmpty else { return }
        index = (index + 1) % matches.count
        select(matchIndex: index)
    }

    private func gotoPrevious() {
        guard !matches.isEmpty else { return }
        index = (index - 1 + matches.count) % matches.count
        select(matchIndex: index)
    }

    private func select(matchIndex i: Int) {
        guard matches.indices.contains(i) else { return }
        view.selectElement(matches[i])
    }

    /// Replace the currently-highlighted match, then advance the
    /// pointer + refresh `matches` so subsequent Replace presses keep
    /// progressing. Refreshing the list is needed because a successful
    /// edit may now match (substring of replacement) or no longer
    /// match — easier to recompute than to maintain incrementally.
    private func replaceCurrent() {
        guard matches.indices.contains(index) else { return }
        let target = matches[index]
        let didEdit = view.replaceCurrent(target, query: query, with: replacement, caseSensitive: caseSensitive)
        guard didEdit else { return }
        // Recompute matches against the new text. Try to keep the user
        // anchored at the same logical spot by re-finding the topic;
        // when it no longer matches, fall back to whatever's at the
        // same index.
        matches = view.findMatches(query: query, caseSensitive: caseSensitive)
        if matches.isEmpty {
            index = 0
        } else if let i = matches.firstIndex(where: { $0 === target }) {
            index = (i + 1) % matches.count
        } else {
            index = min(index, matches.count - 1)
        }
        select(matchIndex: index)
    }

    private func replaceAll() {
        let n = view.replaceAll(query: query, with: replacement, caseSensitive: caseSensitive)
        if n > 0 { refreshMatches() }
    }
}
