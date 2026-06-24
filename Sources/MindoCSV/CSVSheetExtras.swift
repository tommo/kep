import Foundation

/// Per-cell visual styling — the "extra" that does NOT belong in plain CSV.
/// Colors are `#RRGGBB` strings so the sidecar stays human-diffable.
public struct CSVCellStyle: Equatable, Codable, Sendable {
    public var bold: Bool
    public var italic: Bool
    public var background: String?
    public var textColor: String?
    public var align: String?          // "left" | "center" | "right"

    public init(bold: Bool = false, italic: Bool = false,
                background: String? = nil, textColor: String? = nil, align: String? = nil) {
        self.bold = bold; self.italic = italic
        self.background = background; self.textColor = textColor; self.align = align
    }

    /// No styling at all — used to drop empty entries from the sidecar so it
    /// only records cells the user actually styled.
    public var isEmpty: Bool {
        !bold && !italic && background == nil && textColor == nil && align == nil
    }
}

/// A user-composed Lua "sheet block": a named computation over the whole table
/// (shown in the CSV inspector). Its `name` is a Lua identifier, so a block
/// `total = sum(col("A"))` is referenceable from any cell formula as `=total`.
public struct CSVEvalBlock: Equatable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String       // Lua identifier; referenceable as =name
    public var source: String     // Lua chunk; its `return` value is the named result
    public var output: String?    // last captured stdout/result (display cache)

    public init(id: String = UUID().uuidString, name: String, source: String, output: String? = nil) {
        self.id = id
        self.name = name
        self.source = source
        self.output = output
    }
}

/// The extended layer for a CSV document: the formula sources and per-cell
/// styling kept in a sibling sidecar so the `.csv` itself stays plain — it holds
/// only the baked (computed) values, which version-control and merge cleanly.
/// The sidecar is independent JSON keyed by A1 refs, serialized with sorted keys
/// one-per-line so it also merges cell-by-cell.
public struct CSVSheetExtras: Equatable, Codable, Sendable {
    public var version: Int
    /// A1 → formula source (`"=A1*2"`). The matching `.csv` cell holds the
    /// computed value.
    public var formulas: [String: String]
    /// A1 → cell style.
    public var styles: [String: CSVCellStyle]
    /// User-composed sheet blocks (inspector panel), in display order.
    public var blocks: [CSVEvalBlock]

    public init(version: Int = 1,
                formulas: [String: String] = [:],
                styles: [String: CSVCellStyle] = [:],
                blocks: [CSVEvalBlock] = []) {
        self.version = version
        self.formulas = formulas
        self.styles = styles
        self.blocks = blocks
    }

    // Tolerant decoding so sidecars written before a field existed still parse.
    enum CodingKeys: String, CodingKey { case version, formulas, styles, blocks }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        formulas = try c.decodeIfPresent([String: String].self, forKey: .formulas) ?? [:]
        styles = try c.decodeIfPresent([String: CSVCellStyle].self, forKey: .styles) ?? [:]
        blocks = try c.decodeIfPresent([CSVEvalBlock].self, forKey: .blocks) ?? []
    }

    /// Nothing to persist — the document is plain CSV with no extras.
    public var isEmpty: Bool { formulas.isEmpty && styles.isEmpty && blocks.isEmpty }

    // MARK: - Mutation (drops entries that carry no information)

    public mutating func setFormula(_ formula: String?, at a1: String) {
        if let f = formula, f.hasPrefix("=") { formulas[a1] = f } else { formulas.removeValue(forKey: a1) }
    }

    public mutating func setStyle(_ style: CSVCellStyle, at a1: String) {
        if style.isEmpty { styles.removeValue(forKey: a1) } else { styles[a1] = style }
    }

    // MARK: - Serialization (deterministic + merge-friendly)

    public func serialize() -> String {
        let encoder = JSONEncoder()
        // sortedKeys → stable cell order; prettyPrinted → one key per line so a
        // change to one cell is a one-line diff that merges independently.
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(self),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s + "\n"
    }

    public static func parse(_ json: String) -> CSVSheetExtras? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CSVSheetExtras.self, from: data)
    }

    // MARK: - Sidecar location

    /// The sidecar path for a CSV document: `notes.csv` → `.notes.csv.sheet.json`
    /// — a hidden dotfile so the extended layer doesn't clutter the workspace /
    /// Finder, while still sitting next to its data file and unambiguous about
    /// which CSV it belongs to.
    public static func sidecarURL(for csvURL: URL) -> URL {
        csvURL.deletingLastPathComponent()
            .appendingPathComponent("." + csvURL.lastPathComponent + ".sheet.json")
    }

    /// The earlier, NON-hidden sidecar name (`notes.csv.sheet.json`). Kept so the
    /// editor can read + clean up files written before the dotfile change.
    public static func legacySidecarURL(for csvURL: URL) -> URL {
        csvURL.deletingLastPathComponent()
            .appendingPathComponent(csvURL.lastPathComponent + ".sheet.json")
    }
}
