import SwiftUI

/// A structural move requested from the outline (⌥-arrows): reorder among
/// siblings or change depth. The host maps these to undoable reparents.
public enum OutlineMove {
    case up, down, indent, outdent
}

/// Sidebar list rendering of an `[OutlineItem]`. Indents by `depth` and emits
/// a tap on selection. Lightweight: just a SwiftUI `List`; tree disclosure
/// stays out of the way since the indentation already shows hierarchy.
public struct OutlinePanel: View {
    public let items: [OutlineItem]
    /// The `target` of the row to show as selected — driven by the editor's
    /// own selection (e.g. the mind-map canvas) so the outline highlight stays
    /// in sync with the graph. `nil` = no external selection.
    public var selectedTarget: String?
    public let onSelect: (OutlineItem) -> Void
    /// Inline rename callback `(item, newTitle)`. When nil the rows are
    /// read-only (markdown/PlantUML outlines); when set (mind maps) a row can be
    /// edited in place via double-click or Return on the selected row.
    public var onRename: ((OutlineItem, String) -> Void)?
    /// Structural move callback `(item, move)` for ⌥-arrow reorder/reparent.
    /// nil for read-only outlines.
    public var onMove: ((OutlineItem, OutlineMove) -> Void)?
    /// Fold/unfold callback for a row with children (chevron click or ←/→).
    /// nil for read-only outlines.
    public var onToggleCollapse: ((OutlineItem) -> Void)?
    @State private var selection: OutlineItem.ID?
    @State private var filter: String = ""
    /// True while pushing the external `selectedTarget` into `selection`, so the
    /// selection `onChange` doesn't echo it back as a navigation request.
    @State private var syncing = false
    /// The row currently being renamed in place (nil = none).
    @State private var editingID: OutlineItem.ID?
    @State private var editDraft: String = ""
    @FocusState private var editFieldFocused: Bool

    public init(items: [OutlineItem], selectedTarget: String? = nil,
                onSelect: @escaping (OutlineItem) -> Void,
                onRename: ((OutlineItem, String) -> Void)? = nil,
                onMove: ((OutlineItem, OutlineMove) -> Void)? = nil,
                onToggleCollapse: ((OutlineItem) -> Void)? = nil) {
        self.items = items
        self.selectedTarget = selectedTarget
        self.onSelect = onSelect
        self.onRename = onRename
        self.onMove = onMove
        self.onToggleCollapse = onToggleCollapse
    }

    private func beginEdit(_ item: OutlineItem) {
        guard onRename != nil else { return }
        // Commit any row already being edited first — otherwise starting a new
        // edit overwrites the shared draft/editingID and the previous row's
        // focus-loss commit is skipped (its typed rename would be lost).
        if let cur = editingID, cur != item.id, let prev = items.first(where: { $0.id == cur }) {
            commitEdit(prev)
        }
        editDraft = item.title
        editingID = item.id
        editFieldFocused = true
    }

    private func commitEdit(_ item: OutlineItem) {
        guard editingID == item.id else { return }
        editingID = nil
        let trimmed = editDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != item.title else { return }
        onRename?(item, trimmed)
    }

    /// Map the external `selectedTarget` to the (per-render, UUID) row id so the
    /// List highlights it. Recomputed whenever the target or the items change
    /// (the ids are regenerated each time the outline is rebuilt).
    private func syncSelectionFromTarget() {
        syncing = true
        selection = items.first { $0.target == selectedTarget }?.id
        DispatchQueue.main.async { syncing = false }
    }

    public var body: some View {
        if items.isEmpty {
            Text("No outline")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                // Filter bar — case-insensitive substring match against
                // item titles. Empty string passes everything through.
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    TextField("Filter", text: $filter)
                        .textFieldStyle(.plain)
                        .font(.caption)
                    if !filter.isEmpty {
                        Button { filter = "" } label: {
                            Image(systemName: "xmark.circle.fill").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                Divider()
                List(filteredItems, selection: $selection) { item in
                    HStack(spacing: 4) {
                        if item.depth > 1 {
                            Spacer().frame(width: CGFloat((item.depth - 1) * 12))
                        }
                        // Disclosure chevron — only for nodes with children when
                        // folding is supported; a fixed-width gap otherwise keeps
                        // sibling titles aligned.
                        if item.hasChildren && onToggleCollapse != nil {
                            Image(systemName: item.isCollapsed ? "chevron.right" : "chevron.down")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                                .frame(width: 10)
                                .contentShape(Rectangle())
                                .onTapGesture { onToggleCollapse?(item) }
                        } else {
                            Spacer().frame(width: 10)
                        }
                        Image(systemName: icon(for: item.depth))
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                        if editingID == item.id {
                            TextField("", text: $editDraft)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .focused($editFieldFocused)
                                .onSubmit { commitEdit(item) }
                                .onExitCommand { editingID = nil }   // Esc cancels
                                .onChange(of: editFieldFocused) { _, focused in
                                    if !focused { commitEdit(item) }  // commit on focus loss
                                }
                        } else {
                            Text(item.title)
                                .font(.system(size: 11))   // compact outline rows
                                .lineLimit(1)
                                .truncationMode(.tail)
                                // Double-click renames in place (mind maps only —
                                // onRename is nil otherwise). simultaneousGesture so
                                // the List's own selection handling still fires.
                                .simultaneousGesture(TapGesture(count: 2).onEnded { beginEdit(item) })
                            if !item.markers.isEmpty {
                                Spacer(minLength: 4)
                                ForEach(Array(item.markers.enumerated()), id: \.offset) { _, marker in
                                    Image(systemName: marker.symbolName)
                                        .font(.system(size: 9))
                                        .foregroundStyle(color(for: marker.tint))
                                }
                            }
                        }
                    }
                    .tag(item.id)
                    .listRowInsets(EdgeInsets(top: 1, leading: 6, bottom: 1, trailing: 6))
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 20)
                // Keyboard ops on the selected row (List handles plain arrows for
                // selection; we only claim Return and ⌥-arrows). Skipped while
                // editing — the focused TextField owns the keys then.
                .onKeyPress { press in
                    guard editingID == nil, let id = selection,
                          let item = items.first(where: { $0.id == id }) else { return .ignored }
                    if press.key == .return, press.modifiers.isEmpty, onRename != nil {
                        beginEdit(item)
                        return .handled
                    }
                    if press.modifiers.contains(.option), let onMove {
                        switch press.key {
                        case .upArrow:    onMove(item, .up);      return .handled
                        case .downArrow:  onMove(item, .down);    return .handled
                        case .leftArrow:  onMove(item, .outdent); return .handled
                        case .rightArrow: onMove(item, .indent);  return .handled
                        default: break
                        }
                    }
                    // Plain ←/→ fold/unfold the selected node (tree convention).
                    if press.modifiers.isEmpty, item.hasChildren, let onToggleCollapse {
                        if press.key == .leftArrow, !item.isCollapsed { onToggleCollapse(item); return .handled }
                        if press.key == .rightArrow, item.isCollapsed { onToggleCollapse(item); return .handled }
                    }
                    return .ignored
                }
                // Navigate on real selection changes (not the programmatic sync)
                // — drives off List selection so the row shows the normal arrow
                // cursor, not the link/hand cursor an onTapGesture triggers.
                .onChange(of: selection) { _, new in
                    guard !syncing, let id = new,
                          let item = items.first(where: { $0.id == id }) else { return }
                    onSelect(item)
                }
                .onAppear { syncSelectionFromTarget() }
                .onChange(of: selectedTarget) { _, _ in syncSelectionFromTarget() }
                .onChange(of: items) { _, _ in syncSelectionFromTarget() }
            }
        }
    }

    private var filteredItems: [OutlineItem] {
        let trimmed = filter.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    /// Tint for an outline marker — mirrors the canvas marker colors so the
    /// outline reads consistently with the graph.
    private func color(for tint: OutlineMarker.Tint) -> Color {
        switch tint {
        case .priority(let p):
            switch p {
            case 1: return .red
            case 2: return .orange
            case 3: return .yellow
            case 4: return .blue
            default: return .gray
            }
        case .done:    return .green
        case .accent:  return .blue
        case .todo, .neutral: return .secondary
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
