import Foundation

/// Turns a `LayoutResult` into an SVG string, and provides the public entry
/// `renderSequenceSVG(source:isDark:)` that parses → lays out → renders, or
/// returns nil when the source is not a (non-empty) sequence diagram.
public enum SequenceSVGRenderer {

    private enum K {
        static let arrow = 9.0       // arrowhead length
        static let arrowHalf = 4.0   // arrowhead half-width
        static let selfLoop = 32.0   // self-message horizontal reach
        static let labelGap = 4.0    // text baseline above the message line
    }

    /// Public entry. nil ⇒ caller should fall through to the Java path.
    public static func renderSequenceSVG(source: String, isDark: Bool) -> String? {
        guard SequenceParser.diagramKind(source: source) == .sequence else { return nil }
        let parsed = SequenceParser.parse(source)
        guard !parsed.isEmpty, !parsed.actors.isEmpty else { return nil }
        let measurer: TextMeasurer
        #if canImport(AppKit)
        measurer = .system
        #else
        measurer = TextMeasurer { CGSize(width: Double($0.count) * 7, height: 16) }
        #endif
        let layout = SequenceLayout.layout(parsed, measurer: measurer)
        guard !layout.ops.isEmpty else { return nil }
        return render(layout, isDark: isDark)
    }

    /// Pure: LayoutResult → SVG string. Exposed for snapshot tests.
    public static func render(_ layout: LayoutResult, isDark: Bool) -> String {
        let theme: SVGTheme = isDark ? .dark : .light
        var b = SVGBuilder(width: layout.width, height: layout.height, theme: theme)

        // Draw in z-order: group frames (back) → lifelines → activations →
        // notes → messages → actor boxes (front) → title.
        let order: [(DrawOp) -> Int] = []
        _ = order
        func z(_ op: DrawOp) -> Int {
            switch op {
            case .groupFrame: return 0
            case .lifeline: return 1
            case .activation: return 2
            case .divider: return 3
            case .note: return 4
            case .message, .selfMessage: return 5
            case .actorBox: return 6
            case .title: return 7
            }
        }
        for op in layout.ops.enumerated().sorted(by: { (z($0.element), $0.offset) < (z($1.element), $1.offset) }).map(\.element) {
            emit(op, into: &b, theme: theme)
        }
        return b.document()
    }

    private static func emit(_ op: DrawOp, into b: inout SVGBuilder, theme: SVGTheme) {
        switch op {
        case let .actorBox(x, y, w, h, text, _):
            // Clickable: jump to the actor's first occurrence in the source.
            let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? text
            b.beginLink(href: "kep-src:\(encoded)")
            b.rect(x: x, y: y, w: w, h: h, fill: theme.actorFill, stroke: theme.stroke, rx: 3)
            b.text(text, x: x + w / 2, y: y + h / 2 + 4, anchor: "middle")
            b.endLink()

        case let .lifeline(x, y0, y1):
            b.line(x, y0, x, y1, stroke: theme.lifeline, dashed: true)

        case let .activation(x, y, w, h):
            b.rect(x: x, y: y, w: w, h: h, fill: theme.activationFill, stroke: theme.stroke)

        case let .message(fromX, toX, y, dashed, left, right, text):
            b.line(fromX, y, toX, y, stroke: theme.stroke, dashed: dashed)
            let dir = toX >= fromX ? 1.0 : -1.0
            arrowhead(right, tipX: toX, tipY: y, dir: dir, into: &b, theme: theme)
            if left != .none { arrowhead(left, tipX: fromX, tipY: y, dir: -dir, into: &b, theme: theme) }
            if !text.isEmpty {
                let cx = (fromX + toX) / 2
                b.text(text, x: cx, y: y - K.labelGap, anchor: "middle")
            }

        case let .selfMessage(x, y, h, text):
            let right = x + K.selfLoop
            let top = y + 6, bot = y + h - 6
            b.path("M \(fmt(x)) \(fmt(top)) L \(fmt(right)) \(fmt(top)) L \(fmt(right)) \(fmt(bot)) L \(fmt(x)) \(fmt(bot))",
                   stroke: theme.stroke)
            arrowhead(.filled, tipX: x, tipY: bot, dir: -1, into: &b, theme: theme)
            if !text.isEmpty { b.text(text, x: right + 4, y: (top + bot) / 2 + 4, anchor: "start") }

        case let .note(x, y, w, h, text):
            // Folded-corner note (PlantUML style).
            let fold = 8.0
            b.polygon([(x, y), (x + w - fold, y), (x + w, y + fold), (x + w, y + h), (x, y + h)],
                      fill: theme.noteFill, stroke: theme.noteStroke)
            b.polyline([(x + w - fold, y), (x + w - fold, y + fold), (x + w, y + fold)], stroke: theme.noteStroke)
            b.text(text, x: x + w / 2, y: y + h / 2 + 4, anchor: "middle")

        case let .groupFrame(x, y, w, h, kind, label, dividers):
            b.rect(x: x, y: y, w: w, h: h, fill: "none", stroke: theme.groupStroke)
            for dy in dividers { b.line(x, dy, x + w, dy, stroke: theme.groupStroke, dashed: true) }
            // top-left label tab
            let tabW = Double(kind.count) * 8 + 16
            b.polygon([(x, y), (x + tabW, y), (x + tabW, y + 14), (x + tabW - 8, y + 18), (x, y + 18)],
                      fill: theme.groupLabelFill, stroke: theme.groupStroke)
            b.text(kind, x: x + 6, y: y + 13, anchor: "start", bold: true)
            if !label.isEmpty { b.text("[\(label)]", x: x + tabW + 6, y: y + 13, anchor: "start") }

        case let .divider(y, width, text):
            b.line(0, y, width, y, stroke: theme.stroke)
            if !text.isEmpty {
                let w = Double(text.count) * 8 + 16
                b.rect(x: (width - w) / 2, y: y - 9, w: w, h: 18, fill: theme.groupLabelFill, stroke: theme.groupStroke, rx: 2)
                b.text(text, x: width / 2, y: y + 4, anchor: "middle", bold: true)
            }

        case let .title(x, y, text):
            b.text(text, x: x, y: y + 4, anchor: "middle", bold: true)
        }
    }

    private static func fmt(_ v: Double) -> String {
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    private static func arrowhead(_ head: ArrowHead, tipX: Double, tipY: Double, dir: Double,
                                  into b: inout SVGBuilder, theme: SVGTheme) {
        let base = tipX - dir * K.arrow
        switch head {
        case .none: break
        case .filled:
            b.polygon([(tipX, tipY), (base, tipY - K.arrowHalf), (base, tipY + K.arrowHalf)], fill: theme.stroke)
        case .open:
            b.polyline([(base, tipY - K.arrowHalf), (tipX, tipY), (base, tipY + K.arrowHalf)], stroke: theme.stroke)
        case .cross:
            let cx = tipX - dir * K.arrow / 2
            b.line(cx - 4, tipY - 4, cx + 4, tipY + 4, stroke: theme.stroke)
            b.line(cx - 4, tipY + 4, cx + 4, tipY - 4, stroke: theme.stroke)
        case .circle:
            b.circle(tipX - dir * 4, tipY, r: 4, fill: theme.background, stroke: theme.stroke)
        }
    }
}
