import SwiftUI
import AppKit

/// Renders `[MarkdownBlock]` with native, selectable SwiftUI views — nested
/// lists with real indentation, recursive blockquotes, task-list checkboxes,
/// GFM tables, code blocks. No WebView. Theming flows from `MarkdownRenderStyle`.
public struct MarkdownBlocksView: View {
    private let blocks: [MarkdownBlock]
    private let style: MarkdownRenderStyle

    public init(blocks: [MarkdownBlock], style: MarkdownRenderStyle) {
        self.blocks = blocks
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                block(b)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func block(_ b: MarkdownBlock) -> some View {
        switch b {
        case .heading(let level, let text):
            Text(text)
                .font(.system(size: style.bodyFont.pointSize * style.headingScale[min(max(level, 1), 6) - 1],
                              weight: .semibold))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, level <= 2 ? 2 : 0)

        case .paragraph(let text):
            Text(text)
                .font(.system(size: style.bodyFont.pointSize))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .list(let ordered, let start, let items):
            ListView(ordered: ordered, start: start, items: items, style: style)

        case .quote(let inner):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.secondary.opacity(0.4)).frame(width: 3)
                MarkdownBlocksView(blocks: inner, style: style)   // concrete type breaks the opaque recursion
            }

        case .code(_, let text):
            Text(text)
                .font(.system(size: style.monoFont.pointSize, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))

        case .table(let header, let rows, let align):
            TableView(header: header, rows: rows, align: align, style: style)

        case .thematicBreak:
            Divider().padding(.vertical, 2)
        }
    }
}

/// Nested list with markers (•, 1., or a checkbox), recursing into child blocks.
private struct ListView: View {
    let ordered: Bool
    let start: Int
    let items: [MarkdownListItem]
    let style: MarkdownRenderStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    marker(index: i, checkbox: item.checkbox)
                        .frame(minWidth: ordered ? 18 : 12, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, b in
                            MarkdownBlocksView(blocks: [b], style: style)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func marker(index: Int, checkbox: Bool?) -> some View {
        if let checked = checkbox {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .foregroundStyle(checked ? Color.accentColor : .secondary)
                .font(.system(size: style.bodyFont.pointSize * 0.9))
        } else if ordered {
            Text("\(start + index).")
                .font(.system(size: style.bodyFont.pointSize)).foregroundStyle(.secondary)
                .monospacedDigit()
        } else {
            Text("•").font(.system(size: style.bodyFont.pointSize)).foregroundStyle(.secondary)
        }
    }
}

/// GFM table laid out with a Grid, honoring per-column alignment.
private struct TableView: View {
    let header: [AttributedString]
    let rows: [[AttributedString]]
    let align: [MarkdownColumnAlign]
    let style: MarkdownRenderStyle

    private func alignment(_ col: Int) -> Alignment {
        switch align.indices.contains(col) ? align[col] : .leading {
        case .center: return .center; case .trailing: return .trailing; default: return .leading
        }
    }

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            GridRow {
                ForEach(Array(header.enumerated()), id: \.offset) { col, cell in
                    Text(cell).font(.system(size: style.bodyFont.pointSize, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: alignment(col))
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { col, cell in
                        Text(cell).font(.system(size: style.bodyFont.pointSize))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: alignment(col))
                    }
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.03)))
    }
}
