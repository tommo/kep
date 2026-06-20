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

    public init(version: Int = 1,
                formulas: [String: String] = [:],
                styles: [String: CSVCellStyle] = [:]) {
        self.version = version
        self.formulas = formulas
        self.styles = styles
    }

    /// Nothing to persist — the document is plain CSV with no extras.
    public var isEmpty: Bool { formulas.isEmpty && styles.isEmpty }

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
}
