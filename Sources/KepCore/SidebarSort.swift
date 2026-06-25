import Foundation

/// How the file tree orders entries within each folder. Folders always sort
/// before files (alphabetically); the mode only governs the file ordering.
public enum SidebarSortMode: String, CaseIterable, Sendable {
    case name        // A→Z (default)
    case recent      // most-recently-opened first
    case modified    // most-recently-modified first

    public var label: String {
        switch self {
        case .name:     return "Name"
        case .recent:   return "Recently Opened"
        case .modified: return "Date Modified"
        }
    }
}

/// Pure sort for sidebar tree children. Kept here (not in the view) so the
/// ordering is unit-testable on plain `NodeData` arrays.
public enum SidebarSort {
    public static func sorted(_ nodes: [NodeData], mode: SidebarSortMode,
                              recents: [URL] = [],
                              modifiedAt: (URL) -> Date = SidebarSort.fileModifiedDate) -> [NodeData] {
        let byName: (NodeData, NodeData) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        let folders = nodes.filter { $0.isExpandable }.sorted(by: byName)
        var files = nodes.filter { !$0.isExpandable }

        switch mode {
        case .name:
            files.sort(by: byName)
        case .recent:
            let rank = Dictionary(
                recents.enumerated().map { ($1.standardizedFileURL, $0) },
                uniquingKeysWith: { a, _ in a })
            files.sort {
                let r0 = rank[$0.url.standardizedFileURL] ?? Int.max
                let r1 = rank[$1.url.standardizedFileURL] ?? Int.max
                return r0 != r1 ? r0 < r1 : byName($0, $1)
            }
        case .modified:
            files.sort {
                let m0 = modifiedAt($0.url), m1 = modifiedAt($1.url)
                return m0 != m1 ? m0 > m1 : byName($0, $1)
            }
        }
        return folders + files
    }

    public static func fileModifiedDate(_ url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
            .flatMap { $0 } ?? .distantPast
    }
}
