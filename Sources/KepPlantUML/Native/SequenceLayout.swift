import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Positioned drawing primitive in diagram coordinates (origin top-left, +y down).
/// Renderer-agnostic so layout is snapshot-testable without producing SVG.
public enum DrawOp: Equatable, Sendable {
    case actorBox(x: Double, y: Double, w: Double, h: Double, text: String, head: SeqHead)
    case lifeline(x: Double, y0: Double, y1: Double)
    case message(fromX: Double, toX: Double, y: Double, dashed: Bool, left: ArrowHead, right: ArrowHead, text: String)
    case selfMessage(x: Double, y: Double, h: Double, text: String)
    case activation(x: Double, y: Double, w: Double, h: Double)
    case note(x: Double, y: Double, w: Double, h: Double, text: String)
    case groupFrame(x: Double, y: Double, w: Double, h: Double, kind: String, label: String, dividers: [Double])
    case divider(y: Double, width: Double, text: String)
    case title(x: Double, y: Double, text: String)
}

public struct LayoutResult: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public let ops: [DrawOp]
}

/// Text sizing, injected so layout tests use deterministic stub metrics.
public struct TextMeasurer {
    public let measure: (String) -> CGSize
    public init(_ measure: @escaping (String) -> CGSize) { self.measure = measure }

    #if canImport(AppKit)
    /// Production measurer: real glyph metrics with the font the SVG declares.
    public static let system = TextMeasurer { s in
        let font = NSFont.systemFont(ofSize: 13)
        let lines = s.replacingOccurrences(of: "\\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        var w = 0.0, h = 0.0
        for line in lines {
            let r = NSAttributedString(string: String(line), attributes: [.font: font])
                .boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                              options: [.usesLineFragmentOrigin, .usesFontLeading])
            w = max(w, ceil(r.width)); h += ceil(r.height)
        }
        return CGSize(width: max(w, 1), height: max(h, 16))
    }
    #endif
}

/// Pure single-pass sequence-diagram layout. Ports bramp/js-sequence-diagrams'
/// 3-phase approach (measure → constraint propagation → position sweep) plus a
/// mermaid-style bounds stack for nested group frames and a per-actor activation
/// stack. Coordinates in px.
public enum SequenceLayout {
    enum K {
        static let diagramMargin = 10.0, actorMargin = 12.0, actorPadding = 10.0
        static let signalMargin = 6.0, signalPadding = 6.0
        static let noteMargin = 10.0, notePadding = 6.0, noteOverlap = 12.0
        static let selfWidth = 22.0, activationWidth = 10.0
        static let groupInset = 10.0, groupLabelH = 20.0, dividerH = 26.0
    }

    public static func layout(_ d: ParsedSequence, measurer m: TextMeasurer) -> LayoutResult {
        let n = d.actors.count
        guard n > 0 else { return LayoutResult(width: 0, height: 0, ops: []) }

        // ---- Phase 1: measure ----
        let titleH: Double = d.title.map { m.measure($0).height + 2 * K.signalMargin } ?? 0
        var width = [Double](repeating: 0, count: n)
        var headH = 0.0
        for a in d.actors {
            let tb = m.measure(a.name)
            width[a.index] = tb.width + 2 * (K.actorPadding + K.actorMargin)
            headH = max(headH, tb.height + 2 * K.actorPadding)
        }

        // ---- Phase 2: constraint propagation (long labels widen the gap) ----
        var dist: [Int: [Int: Double]] = [:]
        func ensure(_ i: Int, _ j: Int, _ centerDist: Double) {
            guard i != j, i >= 0, j >= 0, i < n, j < n else { return }
            let lo = min(i, j), hi = max(i, j)
            dist[lo, default: [:]][hi] = max(dist[lo]?[hi] ?? 0, centerDist)
        }
        func collect(_ signals: [Signal]) {
            for s in signals {
                switch s {
                case let .message(f, t, _, _, _, text) where f != t:
                    ensure(f, t, m.measure(text).width + 2 * (K.signalMargin + K.signalPadding))
                case let .selfMessage(a, text):
                    ensure(a, a + 1, K.selfWidth + m.measure(text).width + 2 * K.signalPadding)
                case let .note(.over, acts, text) where acts.count >= 2:
                    ensure(acts.min()!, acts.max()!, m.measure(text).width + 2 * (K.noteMargin + K.notePadding) - 2 * K.noteOverlap)
                case let .group(_, _, sections):
                    for sec in sections { collect(sec.signals) }
                default: break
                }
            }
        }
        collect(d.signals)

        // ---- Phase 3: position sweep ----
        var x = [Double](repeating: 0, count: n)
        var running = K.diagramMargin
        for i in 0..<n {
            x[i] = max(running, x[i])
            if let row = dist[i] {
                for (j, need) in row where j > i {
                    x[j] = max(x[j], x[i] + width[i] / 2 + need - width[j] / 2)
                }
            }
            running = x[i] + width[i] + K.actorMargin
        }
        func cx(_ i: Int) -> Double { x[i] + width[i] / 2 }
        let diagramWidth = x[n - 1] + width[n - 1] + K.diagramMargin

        // ---- Vertical flow ----
        var ops: [DrawOp] = []
        if let t = d.title { ops.append(.title(x: diagramWidth / 2, y: K.diagramMargin + m.measure(t).height / 2, text: t)) }

        let headTop = K.diagramMargin + titleH
        let bodyTop = headTop + headH
        var y = bodyTop + K.signalMargin

        struct Frame { let kind: String; let label: String; let startY: Double; var minIdx: Int; var maxIdx: Int; var dividers: [Double] }
        var frames: [Frame] = []
        var actStack = [[Double]](repeating: [], count: n)
        func touch(_ indices: Int...) {
            guard !frames.isEmpty else { return }
            for k in frames.indices {
                for idx in indices { frames[k].minIdx = min(frames[k].minIdx, idx); frames[k].maxIdx = max(frames[k].maxIdx, idx) }
            }
        }

        func walk(_ signals: [Signal]) {
            for s in signals {
                switch s {
                case let .message(f, t, dashed, lh, rh, text):
                    let h = m.measure(text).height + 2 * K.signalMargin
                    ops.append(.message(fromX: cx(f), toX: cx(t), y: y + h - K.signalMargin,
                                        dashed: dashed, left: lh, right: rh, text: text))
                    y += h; touch(f, t)
                case let .selfMessage(a, text):
                    let h = m.measure(text).height + K.selfWidth
                    ops.append(.selfMessage(x: cx(a), y: y, h: h, text: text))
                    y += h + K.signalMargin; touch(a)
                case let .note(placement, acts, text):
                    let tb = m.measure(text)
                    let h = tb.height + 2 * K.notePadding
                    let (nx, nw): (Double, Double)
                    switch placement {
                    case .over where acts.count >= 2:
                        let lo = acts.min()!, hi = acts.max()!
                        nx = cx(lo) - K.noteOverlap; nw = (cx(hi) + K.noteOverlap) - nx
                    case .over:
                        let w = tb.width + 2 * K.notePadding; nx = cx(acts.first ?? 0) - w / 2; nw = w
                    case .rightOf:
                        let w = tb.width + 2 * K.notePadding; nx = cx(acts.first ?? 0) + K.noteMargin; nw = w
                    case .leftOf:
                        let w = tb.width + 2 * K.notePadding; nx = cx(acts.first ?? 0) - K.noteMargin - w; nw = w
                    }
                    ops.append(.note(x: nx, y: y, w: nw, h: h, text: text))
                    y += h + K.noteMargin; if !acts.isEmpty { touch(acts.min()!, acts.max()!) }
                case let .activate(a):
                    actStack[a].append(y)
                case let .deactivate(a):
                    if let top = actStack[a].popLast() {
                        let depth = Double(actStack[a].count)
                        ops.append(.activation(x: cx(a) - K.activationWidth / 2 + depth * K.activationWidth / 2,
                                               y: top, w: K.activationWidth, h: max(y - top, K.signalMargin)))
                    }
                case let .divider(text):
                    ops.append(.divider(y: y + K.dividerH / 2, width: diagramWidth, text: text)); y += K.dividerH
                case let .space(hgt):
                    y += hgt
                case let .group(kind, label, sections):
                    let f = Frame(kind: kind, label: label, startY: y, minIdx: n, maxIdx: -1, dividers: [])
                    frames.append(f)
                    y += K.groupLabelH
                    for (i, sec) in sections.enumerated() {
                        if i > 0 { frames[frames.count - 1].dividers.append(y); y += m.measure(sec.elseLabel ?? "").height }
                        walk(sec.signals)
                    }
                    y += K.groupInset
                    let done = frames.removeLast()
                    let lo = done.maxIdx >= 0 ? done.minIdx : 0
                    let hi = done.maxIdx >= 0 ? done.maxIdx : max(0, n - 1)
                    let fx = cx(lo) - K.groupInset - K.activationWidth
                    let fw = (cx(hi) + K.groupInset + K.activationWidth) - fx
                    ops.append(.groupFrame(x: fx, y: done.startY, w: fw, h: y - done.startY,
                                          kind: done.kind, label: done.label, dividers: done.dividers))
                    // a frame's actors also count toward an enclosing frame
                    touch(lo, hi)
                }
            }
        }
        walk(d.signals)
        // Close any still-open activations.
        for a in 0..<n {
            while let top = actStack[a].popLast() {
                ops.append(.activation(x: cx(a) - K.activationWidth / 2, y: top, w: K.activationWidth, h: max(y - top, K.signalMargin)))
            }
        }

        // Lifelines + actor heads (top + mirrored bottom).
        let lifeBottom = y
        for a in d.actors {
            ops.append(.lifeline(x: cx(a.index), y0: bodyTop, y1: lifeBottom))
            let bw = width[a.index] - 2 * K.actorMargin
            ops.append(.actorBox(x: x[a.index] + K.actorMargin, y: headTop, w: bw, h: headH, text: a.name, head: a.head))
            ops.append(.actorBox(x: x[a.index] + K.actorMargin, y: lifeBottom, w: bw, h: headH, text: a.name, head: a.head))
        }
        let totalH = lifeBottom + headH + K.diagramMargin
        return LayoutResult(width: diagramWidth, height: totalH, ops: ops)
    }
}
