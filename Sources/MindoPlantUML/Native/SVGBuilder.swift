import Foundation

/// Light/dark palette for the native renderer. Colours mirror PlantUML's
/// default skin (light) and a muted dark variant that matches the preview's
/// dark background.
public struct SVGTheme: Sendable {
    public let background: String
    public let stroke: String          // lines, box borders
    public let actorFill: String       // participant/actor head box
    public let lifeline: String        // dashed lifeline
    public let text: String
    public let noteFill: String
    public let noteStroke: String
    public let groupStroke: String
    public let groupLabelFill: String
    public let activationFill: String

    public static let light = SVGTheme(
        background: "#ffffff", stroke: "#383838", actorFill: "#e2e2f0",
        lifeline: "#aaaaaa", text: "#1a1a1a", noteFill: "#fbfb77",
        noteStroke: "#a9a906", groupStroke: "#888888", groupLabelFill: "#eeeeee",
        activationFill: "#dcdcdc")

    public static let dark = SVGTheme(
        background: "#1e1e1e", stroke: "#c8c8c8", actorFill: "#34344a",
        lifeline: "#6a6a6a", text: "#e6e6e6", noteFill: "#4a4a2c",
        noteStroke: "#b3b34d", groupStroke: "#777777", groupLabelFill: "#2c2c2c",
        activationFill: "#3a3a3a")
}

/// Minimal, allocation-light SVG string emitter. No dependency on the layout
/// model so it can back a future class/box renderer too.
public struct SVGBuilder {
    private var body = ""
    public let width: Double
    public let height: Double
    public let theme: SVGTheme

    public init(width: Double, height: Double, theme: SVGTheme) {
        self.width = width; self.height = height; self.theme = theme
    }

    public static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }

    private static func f(_ v: Double) -> String {
        // Trim to 2 decimals, drop trailing zeros — keeps the SVG compact and
        // snapshot output stable.
        let r = (v * 100).rounded() / 100
        return r == r.rounded() ? String(Int(r)) : String(r)
    }

    public mutating func rect(x: Double, y: Double, w: Double, h: Double,
                              fill: String, stroke: String? = nil, rx: Double = 0, dashed: Bool = false) {
        var s = "<rect x=\"\(Self.f(x))\" y=\"\(Self.f(y))\" width=\"\(Self.f(w))\" height=\"\(Self.f(h))\" fill=\"\(fill)\""
        if rx > 0 { s += " rx=\"\(Self.f(rx))\"" }
        if let stroke { s += " stroke=\"\(stroke)\" stroke-width=\"1\"" }
        if dashed { s += " stroke-dasharray=\"5,4\"" }
        s += "/>"
        body += s
    }

    public mutating func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double,
                              stroke: String, dashed: Bool = false, width sw: Double = 1) {
        var s = "<line x1=\"\(Self.f(x1))\" y1=\"\(Self.f(y1))\" x2=\"\(Self.f(x2))\" y2=\"\(Self.f(y2))\" stroke=\"\(stroke)\" stroke-width=\"\(Self.f(sw))\""
        if dashed { s += " stroke-dasharray=\"5,4\"" }
        s += "/>"
        body += s
    }

    public mutating func polygon(_ points: [(Double, Double)], fill: String, stroke: String? = nil) {
        let pts = points.map { "\(Self.f($0.0)),\(Self.f($0.1))" }.joined(separator: " ")
        var s = "<polygon points=\"\(pts)\" fill=\"\(fill)\""
        if let stroke { s += " stroke=\"\(stroke)\"" }
        s += "/>"
        body += s
    }

    public mutating func polyline(_ points: [(Double, Double)], stroke: String, width sw: Double = 1) {
        let pts = points.map { "\(Self.f($0.0)),\(Self.f($0.1))" }.joined(separator: " ")
        body += "<polyline points=\"\(pts)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"\(Self.f(sw))\"/>"
    }

    public mutating func path(_ d: String, stroke: String, dashed: Bool = false) {
        var s = "<path d=\"\(d)\" fill=\"none\" stroke=\"\(stroke)\" stroke-width=\"1\""
        if dashed { s += " stroke-dasharray=\"5,4\"" }
        s += "/>"
        body += s
    }

    public mutating func circle(_ cx: Double, _ cy: Double, r: Double, fill: String, stroke: String? = nil) {
        var s = "<circle cx=\"\(Self.f(cx))\" cy=\"\(Self.f(cy))\" r=\"\(Self.f(r))\" fill=\"\(fill)\""
        if let stroke { s += " stroke=\"\(stroke)\"" }
        s += "/>"
        body += s
    }

    /// Multi-line aware text. `anchor` is start|middle|end. y is the baseline
    /// of the first line.
    public mutating func text(_ string: String, x: Double, y: Double,
                              anchor: String = "middle", bold: Bool = false, color: String? = nil) {
        let lines = string.replacingOccurrences(of: "\\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
        let fill = color ?? theme.text
        var s = "<text x=\"\(Self.f(x))\" y=\"\(Self.f(y))\" fill=\"\(fill)\" font-family=\"-apple-system, Helvetica, Arial, sans-serif\" font-size=\"13\" text-anchor=\"\(anchor)\""
        if bold { s += " font-weight=\"bold\"" }
        s += ">"
        if lines.count <= 1 {
            s += Self.escape(string)
        } else {
            for (i, ln) in lines.enumerated() {
                s += "<tspan x=\"\(Self.f(x))\" dy=\"\(i == 0 ? "0" : "16")\">\(Self.escape(String(ln)))</tspan>"
            }
        }
        s += "</text>"
        body += s
    }

    public func document() -> String {
        let w = Self.f(width), h = Self.f(height)
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(w)\" height=\"\(h)\" viewBox=\"0 0 \(w) \(h)\">"
            + "<rect x=\"0\" y=\"0\" width=\"\(w)\" height=\"\(h)\" fill=\"\(theme.background)\"/>"
            + body + "</svg>"
    }
}
