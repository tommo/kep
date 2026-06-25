import Foundation
import KepScript

/// Ties a plain `CSVDocument` (which holds only baked/computed values) to its
/// extended layer (`CSVSheetExtras`: formulas + styling), and recomputes
/// formula results through the embedded Lua engine.
///
/// The persistence contract (what the user asked for): the `.csv` is written
/// with the *baked values* so it's plain and merge-friendly; the formulas +
/// styles live in the sidecar. On load we parse the values from the `.csv` and
/// the formulas from the sidecar; a `recompute()` re-bakes the formula cells.
public final class CSVSheet {
    public let document: CSVDocument
    public var extras: CSVSheetExtras

    public init(document: CSVDocument, extras: CSVSheetExtras = CSVSheetExtras()) {
        self.document = document
        self.extras = extras
    }

    /// Load from the plain CSV text and the (optional) sidecar JSON.
    public static func load(csv: String, sidecar: String?, hasHeader: Bool = true) -> CSVSheet {
        let doc = CSVDocument.parse(csv, hasHeader: hasHeader)
        let extras = sidecar.flatMap(CSVSheetExtras.parse) ?? CSVSheetExtras()
        return CSVSheet(document: doc, extras: extras)
    }

    /// The plain CSV text to write to `<name>.csv` — baked values only.
    public func bakedCSV() -> String { document.serialize() }

    /// The sidecar JSON to write to `<name>.csv.sheet.json`, or nil when there
    /// are no extras (so we don't litter the workspace with empty sidecars).
    public func sidecarJSON() -> String? { extras.isEmpty ? nil : extras.serialize() }

    // MARK: - Cell access by A1

    public func value(at ref: CSVCellRef) -> String {
        guard ref.row >= 0, ref.row < document.rows.count,
              ref.col >= 0, ref.col < document.rows[ref.row].count else { return "" }
        return document.rows[ref.row][ref.col]
    }

    /// The raw content the formula engine should see for a cell: its formula
    /// source if it has one, otherwise the plain value baked into the CSV.
    private func content(_ a1: String) -> String? {
        if let f = extras.formulas[a1] { return f }
        guard let ref = CSVCellRef(a1: a1) else { return nil }
        return value(at: ref)
    }

    // MARK: - Recompute

    /// Re-evaluate every formula cell and bake the result back into the document
    /// rows. Call after editing a formula or any cell a formula depends on.
    /// No-op (and no Lua engine spun up) when the sheet has no formulas.
    @discardableResult
    public func recompute() -> Bool {
        guard !extras.formulas.isEmpty else { return false }
        guard let engine = try? LuaFormula(
            content: { [weak self] in self?.content($0) },
            expandRange: { a, b in CSVCellRef.parseRange("\(a):\(b)")?.map(\.a1) ?? [] }
        ) else { return false }

        // Run sheet blocks first and inject each one's result as a named global,
        // so cells can reference a block by name (`=total`). Blocks read the
        // current baked values; a block fed by a formula cell converges over the
        // next recompute (one-pass lag, acceptable for the common literal-data case).
        for r in CSVBlockRunner.run(extras.blocks, over: document) where r.error == nil {
            engine.define(r.name, Double(r.value).map { .number($0) } ?? .text(r.value))
        }

        for a1 in extras.formulas.keys {
            guard let ref = CSVCellRef(a1: a1) else { continue }
            let baked = LuaFormula.display(engine.value(of: a1))
            document.setCell(row: ref.row, column: ref.col, to: baked)
        }
        return true
    }

    // MARK: - Editing

    /// Set a cell to a literal value or a formula. A `=…` string is recorded in
    /// the extended layer and the baked value recomputed; anything else clears
    /// any prior formula and writes the literal straight into the CSV.
    public func setCell(_ ref: CSVCellRef, to input: String) {
        if input.hasPrefix("=") {
            extras.setFormula(input, at: ref.a1)
            recompute()
        } else {
            extras.setFormula(nil, at: ref.a1)
            document.setCell(row: ref.row, column: ref.col, to: input)
            recompute()   // dependents of this cell may need re-baking
        }
    }

    /// The formula source for a cell (what the formula bar should show when the
    /// cell is selected), or nil if the cell is a plain value.
    public func formula(at ref: CSVCellRef) -> String? { extras.formulas[ref.a1] }

    public func style(at ref: CSVCellRef) -> CSVCellStyle? { extras.styles[ref.a1] }

    public func setStyle(_ style: CSVCellStyle, at ref: CSVCellRef) {
        extras.setStyle(style, at: ref.a1)
    }
}
