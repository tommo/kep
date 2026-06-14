import Foundation

public enum CSVFindDirection {
    case forward
    case backward
}

/// Pure, stateless next/previous-match navigator over the row-major match
/// list from `CSVMatcher`. Wrap-around is IMMEDIATE (single key press),
/// fixing javamind's quirk where a match behind the cursor needed an extra
/// press. The current match is skipped so repeated Find-Next walks every
/// hit. `current` is the cell the user is on (nil = fresh search).
public enum CSVFindNavigator {
    public static func next(
        matches: [CSVMatch],
        after current: CSVMatch?,
        direction: CSVFindDirection
    ) -> CSVMatch? {
        guard !matches.isEmpty else { return nil }
        guard let current else {
            return direction == .forward ? matches.first : matches.last
        }
        switch direction {
        case .forward:
            return matches.first { isAfter($0, current) } ?? matches.first
        case .backward:
            return matches.last { isBefore($0, current) } ?? matches.last
        }
    }

    /// Row-major strict ordering: a is after b if it's on a later row, or the
    /// same row and a later column.
    private static func isAfter(_ a: CSVMatch, _ b: CSVMatch) -> Bool {
        a.row > b.row || (a.row == b.row && a.column > b.column)
    }

    private static func isBefore(_ a: CSVMatch, _ b: CSVMatch) -> Bool {
        a.row < b.row || (a.row == b.row && a.column < b.column)
    }
}
