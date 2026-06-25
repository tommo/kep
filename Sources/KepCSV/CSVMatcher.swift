import Foundation

/// A find match at a document cell.
public struct CSVMatch: Equatable {
    public let row: Int
    public let column: Int
    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}

/// Pure substring matcher over the grid, scanning strict row-major order
/// (left-to-right, top-to-bottom). Substring `contains`, not regex, not
/// whole-cell. `rows` includes the header; the caller decides whether to
/// skip row 0. There is no stub row/column in kep, so unlike javamind the
/// last blank growth cells are simply absent.
public enum CSVMatcher {

    public static func matches(in rows: [[String]], keyword: String, caseSensitive: Bool) -> [CSVMatch] {
        guard !keyword.isEmpty else { return [] }    // empty contains-everything guard
        var result: [CSVMatch] = []
        for (r, row) in rows.enumerated() {
            for (c, value) in row.enumerated() {
                if contains(value, keyword, caseSensitive: caseSensitive) {
                    result.append(CSVMatch(row: r, column: c))
                }
            }
        }
        return result
    }

    /// Cheap "is the keyword anywhere in the grid" guard before a replace-all.
    public static func contains(_ rows: [[String]], keyword: String, caseSensitive: Bool) -> Bool {
        guard !keyword.isEmpty else { return false }
        for row in rows where row.contains(where: { contains($0, keyword, caseSensitive: caseSensitive) }) {
            return true
        }
        return false
    }

    static func contains(_ value: String, _ keyword: String, caseSensitive: Bool) -> Bool {
        guard !keyword.isEmpty else { return false }
        return value.range(of: keyword,
                           options: caseSensitive ? [] : [.caseInsensitive]) != nil
    }
}
