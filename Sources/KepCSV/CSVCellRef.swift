import Foundation

/// A spreadsheet cell coordinate, 0-based internally, that round-trips through
/// A1 notation (column letters + 1-based row). The formula engine and the
/// extended-layer (`CSVSheetExtras`) both key cells by A1 so the sidecar is
/// human-readable and merge-friendly.
public struct CSVCellRef: Hashable, Comparable, Sendable {
    public let row: Int   // 0-based
    public let col: Int   // 0-based

    public init(row: Int, col: Int) {
        self.row = row
        self.col = col
    }

    /// Parse `"A1"`, `"B3"`, `"$A$1"`, `"aa12"` → a 0-based ref. Absolute
    /// markers (`$`) are accepted and ignored (kep has no fill-handle yet, so
    /// relative/absolute behave the same). nil for anything malformed.
    public init?(a1: String) {
        var letters = ""
        var digits = ""
        for ch in a1 where ch != "$" {
            if ch.isLetter { if !digits.isEmpty { return nil }; letters.append(ch) }
            else if ch.isNumber { digits.append(ch) }
            else { return nil }
        }
        guard !letters.isEmpty, !digits.isEmpty,
              let col = Self.columnIndex(letters),
              let oneBasedRow = Int(digits), oneBasedRow >= 1 else { return nil }
        self.row = oneBasedRow - 1
        self.col = col
    }

    /// A1 string for this ref, e.g. `(0,0)` → `"A1"`.
    public var a1: String { "\(Self.columnLabel(col))\(row + 1)" }

    public static func < (lhs: CSVCellRef, rhs: CSVCellRef) -> Bool {
        lhs.row != rhs.row ? lhs.row < rhs.row : lhs.col < rhs.col
    }

    // MARK: - Column letters (base-26 bijective: A..Z, AA..AZ, …)

    /// 0 → "A", 25 → "Z", 26 → "AA". Negative → "".
    public static func columnLabel(_ col: Int) -> String {
        guard col >= 0 else { return "" }
        var n = col
        var label = ""
        repeat {
            let rem = n % 26
            label = String(UnicodeScalar(UInt8(65 + rem))) + label
            n = n / 26 - 1
        } while n >= 0
        return label
    }

    /// "A" → 0, "Z" → 25, "AA" → 26. Case-insensitive. nil for non-letters.
    public static func columnIndex(_ label: String) -> Int? {
        guard !label.isEmpty else { return nil }
        var n = 0
        for ch in label.uppercased() {
            guard let a = ch.asciiValue, a >= 65, a <= 90 else { return nil }
            n = n * 26 + Int(a - 65) + 1
        }
        return n - 1
    }

    // MARK: - Ranges

    /// Expand `"A1:B3"` into every cell it covers (row-major order). A single
    /// ref `"A1"` returns `[A1]`. nil if either endpoint is malformed.
    public static func parseRange(_ s: String) -> [CSVCellRef]? {
        let parts = s.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 1 {
            return CSVCellRef(a1: String(parts[0])).map { [$0] }
        }
        guard parts.count == 2,
              let a = CSVCellRef(a1: String(parts[0])),
              let b = CSVCellRef(a1: String(parts[1])) else { return nil }
        let r0 = min(a.row, b.row), r1 = max(a.row, b.row)
        let c0 = min(a.col, b.col), c1 = max(a.col, b.col)
        var out: [CSVCellRef] = []
        for r in r0...r1 { for c in c0...c1 { out.append(CSVCellRef(row: r, col: c)) } }
        return out
    }
}
