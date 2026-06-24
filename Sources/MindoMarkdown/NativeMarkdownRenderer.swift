import SwiftUI
import AppKit
import Markdown
import MindoBase
import MindoCore

/// Native (no-WebView) markdown rendering for kep's inline surfaces — notebook
/// prose cells, agent results, AI dialog. Built on the swift-markdown AST (the
/// existing dependency), so it gets CommonMark + GFM tables / strikethrough /
/// task-lists for free, and replaces the hand-rolled `ProseMarkdown` line
/// classifier (which flattened nested/ordered lists, quotes, tables, …).
///
/// `blocks(_:)` returns a layout model that `MarkdownBlocksView` renders with
/// selectable, themeable SwiftUI `Text` — no per-cell WebView.

public struct MarkdownRenderStyle: Sendable {
    public var bodyFont: NSFont
    public var monoFont: NSFont
    public var palette: SyntaxPalette
    /// Heading size multipliers for levels 1…6.
    public var headingScale: [CGFloat]

    public init(bodyFont: NSFont, monoFont: NSFont, palette: SyntaxPalette,
                headingScale: [CGFloat] = [1.6, 1.4, 1.22, 1.1, 1.0, 1.0]) {
        self.bodyFont = bodyFont
        self.monoFont = monoFont
        self.palette = palette
        self.headingScale = headingScale
    }

    /// Resolve against the current appearance (+ any custom editor theme via
    /// SyntaxPalette), so native rendered text matches the source editor.
    @MainActor public static func resolved(dark: Bool,
                                           base: NSFont = .systemFont(ofSize: NSFont.systemFontSize)) -> MarkdownRenderStyle {
        MarkdownRenderStyle(bodyFont: base,
                            monoFont: .monospacedSystemFont(ofSize: base.pointSize, weight: .regular),
                            palette: .resolved(dark: dark))
    }
}

public enum MarkdownColumnAlign: Sendable { case leading, center, trailing }

public struct MarkdownListItem: Sendable {
    public let checkbox: Bool?          // nil = not a task item
    public let blocks: [MarkdownBlock]
}

public indirect enum MarkdownBlock: Sendable {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])
    case quote([MarkdownBlock])
    case code(language: String?, text: String)
    case table(header: [AttributedString], rows: [[AttributedString]], align: [MarkdownColumnAlign])
    case thematicBreak
}

public enum NativeMarkdownRenderer {

    /// Full block model for native layout (notebook prose, agent results).
    /// `linkifyWiki` rewrites `[[wiki links]]` to `mindo-wiki:` links first (so
    /// MarkdownBlocksView's openURL handler can route taps).
    @MainActor public static func blocks(_ markdown: String, style: MarkdownRenderStyle,
                                         linkifyWiki: Bool = false) -> [MarkdownBlock] {
        let src = linkifyWiki ? WikiLinkMarkdown.linkify(markdown) : markdown
        return Builder(style: style).blocks(of: Document(parsing: src, options: []))
    }

    /// Inline-only fast path (AI dialog while streaming): paragraphs joined by
    /// blank lines into one AttributedString, no block layout.
    @MainActor public static func attributedString(_ markdown: String, style: MarkdownRenderStyle,
                                                    linkifyWiki: Bool = false) -> AttributedString {
        let b = Builder(style: style)
        let src = linkifyWiki ? WikiLinkMarkdown.linkify(markdown) : markdown
        var out = AttributedString()
        for block in b.blocks(of: Document(parsing: src, options: [])) {
            if !out.characters.isEmpty { out += AttributedString("\n\n") }
            switch block {
            case .heading(_, let t), .paragraph(let t): out += t
            case .code(_, let text): out += AttributedString(text)
            default: out += AttributedString(block.plainFallback)
            }
        }
        return out
    }

    // MARK: - AST → model

    private struct Builder {
        let style: MarkdownRenderStyle

        func blocks(of container: Markup) -> [MarkdownBlock] {
            var out: [MarkdownBlock] = []
            for child in container.children {
                switch child {
                case let h as Heading:        out.append(.heading(level: h.level, text: inline(h)))
                case let p as Paragraph:      out.append(.paragraph(inline(p)))
                case let ul as UnorderedList: out.append(.list(ordered: false, start: 1, items: items(ul)))
                case let ol as OrderedList:   out.append(.list(ordered: true, start: Int(ol.startIndex), items: items(ol)))
                case let q as BlockQuote:     out.append(.quote(blocks(of: q)))
                case let cb as CodeBlock:     out.append(.code(language: cb.language, text: cb.code.trimmingTrailingNewline))
                case let t as Markdown.Table: out.append(table(t))
                case is ThematicBreak:        out.append(.thematicBreak)
                default:                      out.append(contentsOf: blocks(of: child))   // unwrap unknowns
                }
            }
            return out
        }

        private func items(_ list: Markup) -> [MarkdownListItem] {
            list.children.compactMap { $0 as? ListItem }.map {
                MarkdownListItem(checkbox: $0.checkbox.map { $0 == .checked }, blocks: blocks(of: $0))
            }
        }

        private func table(_ t: Markdown.Table) -> MarkdownBlock {
            let header = t.head.children.compactMap { $0 as? Markdown.Table.Cell }.map { inline($0) }
            let rows = t.body.children.compactMap { $0 as? Markdown.Table.Row }.map { row in
                row.children.compactMap { $0 as? Markdown.Table.Cell }.map { inline($0) }
            }
            let align: [MarkdownColumnAlign] = t.columnAlignments.map {
                switch $0 { case .center: return .center; case .right: return .trailing; default: return .leading }
            }
            return .table(header: header, rows: rows, align: align)
        }

        // MARK: inline → AttributedString

        func inline(_ markup: Markup) -> AttributedString {
            var out = AttributedString()
            for child in markup.children { out += inlineNode(child) }
            return out
        }

        private func inlineNode(_ node: Markup) -> AttributedString {
            switch node {
            case let t as Markdown.Text:    return AttributedString(t.string)
            case let e as Emphasis:         return withIntent(inline(e), .emphasized)
            case let s as Strong:           return withIntent(inline(s), .stronglyEmphasized)
            case let st as Strikethrough:   return withIntent(inline(st), .strikethrough)
            case let c as InlineCode:
                var a = AttributedString(c.code)
                a.inlinePresentationIntent = .code
                a.foregroundColor = Color(style.palette.string)
                return a
            case let l as Markdown.Link:
                var a = inline(l)
                if let dest = l.destination, let url = URL(string: dest) { a.link = url }
                a.foregroundColor = Color(style.palette.link)
                return a
            case let img as Markdown.Image:
                let alt = String(inline(img).characters)
                return AttributedString("🖼 " + (alt.isEmpty ? (img.source ?? "image") : alt))
            case is SoftBreak:              return AttributedString(" ")
            case is LineBreak:              return AttributedString("\n")
            case let ih as InlineHTML:      return AttributedString(ih.rawHTML)
            default:                        return inline(node)   // unwrap unknown inline containers
            }
        }

        /// Union an inline intent across every run (so bold-inside-italic etc.
        /// combine rather than overwrite).
        private func withIntent(_ s: AttributedString, _ intent: InlinePresentationIntent) -> AttributedString {
            var copy = s
            for run in copy.runs {
                let existing = copy[run.range].inlinePresentationIntent ?? []
                copy[run.range].inlinePresentationIntent = existing.union(intent)
            }
            return copy
        }
    }
}

private extension MarkdownBlock {
    var plainFallback: String {
        switch self {
        case .heading(_, let t), .paragraph(let t): return String(t.characters)
        case .code(_, let text): return text
        case .list(_, _, let items): return items.map { $0.blocks.map(\.plainFallback).joined(separator: " ") }.joined(separator: "\n")
        case .quote(let b): return b.map(\.plainFallback).joined(separator: "\n")
        case .table(let header, let rows, _):
            return ([header] + rows).map { $0.map { String($0.characters) }.joined(separator: " | ") }.joined(separator: "\n")
        case .thematicBreak: return "———"
        }
    }
}

private extension String {
    var trimmingTrailingNewline: String {
        hasSuffix("\n") ? String(dropLast()) : self
    }
}
