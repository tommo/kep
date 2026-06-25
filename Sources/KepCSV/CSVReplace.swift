import Foundation

/// Pure replace logic operating PER CELL on unescaped values — never on the
/// serialized CSV — which fixes javamind's replace-all (a raw string replace
/// over serialized CSV that could corrupt quoting/grammar). Case sensitivity
/// uses the same primitive as `CSVMatcher` so a replace can't desync from
/// the match that found it.
public enum CSVReplace {

    /// Replace every occurrence of `keyword` within one cell value. An empty
    /// `replacement` deletes the matched substring. Empty keyword is a no-op.
    public static func replaceInCell(_ value: String, keyword: String,
                                     with replacement: String, caseSensitive: Bool) -> String {
        guard !keyword.isEmpty else { return value }
        return value.replacingOccurrences(
            of: keyword,
            with: replacement,
            options: caseSensitive ? [] : [.caseInsensitive]
        )
    }

    /// Whether this cell currently contains the keyword (the precondition for
    /// a one-at-a-time replace).
    public static func cellContains(_ value: String, keyword: String, caseSensitive: Bool) -> Bool {
        CSVMatcher.contains(value, keyword, caseSensitive: caseSensitive)
    }

    /// Plan a global per-cell replace: a write for every cell whose value
    /// changes. `rows` includes the header. Unchanged cells are omitted.
    public static func planReplaceAll(in rows: [[String]], keyword: String,
                                      with replacement: String, caseSensitive: Bool) -> [CSVCellWrite] {
        guard !keyword.isEmpty else { return [] }
        var writes: [CSVCellWrite] = []
        for (r, row) in rows.enumerated() {
            for (c, value) in row.enumerated() {
                let replaced = replaceInCell(value, keyword: keyword, with: replacement, caseSensitive: caseSensitive)
                if replaced != value {
                    writes.append(CSVCellWrite(row: r, column: c, value: replaced))
                }
            }
        }
        return writes
    }
}
