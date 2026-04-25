import Foundation
import MindoCore

/// User- or built-in-defined snippet that can be inserted into an editor.
/// Mirrors `Snippet` from `mindolph-core/model`.
public struct Snippet: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    /// File type this snippet applies to. `nil` means "any".
    public var fileType: SupportedFileType?
    public var tags: [String]
    /// Whether the snippet is bundled with Mindo (read-only) or user-defined.
    public var isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        fileType: SupportedFileType? = nil,
        tags: [String] = [],
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.fileType = fileType
        self.tags = tags
        self.isBuiltIn = isBuiltIn
    }
}

/// Loads, stores, and seeds snippets. JSON-persisted at
/// `~/Library/Application Support/Mindo/snippets.json` (configurable for
/// tests). Built-in seeds cover the most common Markdown / PlantUML /
/// MindMap starting points.
@MainActor
public final class SnippetStore: ObservableObject {
    @Published public private(set) var userSnippets: [Snippet]
    public let builtIn: [Snippet]
    private let url: URL

    public init(directory: URL = SnippetStore.defaultDirectory) {
        self.url = directory.appendingPathComponent("snippets.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([Snippet].self, from: data) {
            self.userSnippets = decoded
        } else {
            self.userSnippets = []
        }
        self.builtIn = SnippetStore.bundledSnippets()
    }

    public nonisolated static var defaultDirectory: URL {
        MindoCore.applicationSupportURL
    }

    /// Combined snippet list — built-in first, then user.
    public var all: [Snippet] { builtIn + userSnippets }

    /// Filter by file type and case-insensitive search query.
    public func filter(fileType: SupportedFileType?, query: String) -> [Snippet] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return all.filter { snippet in
            if let want = fileType {
                if snippet.fileType != nil && snippet.fileType != want { return false }
            }
            if q.isEmpty { return true }
            if snippet.title.lowercased().contains(q) { return true }
            if snippet.body.lowercased().contains(q) { return true }
            if snippet.tags.contains(where: { $0.lowercased().contains(q) }) { return true }
            return false
        }
    }

    public func add(_ snippet: Snippet) {
        var s = snippet
        s.isBuiltIn = false
        userSnippets.removeAll { $0.id == s.id }
        userSnippets.append(s)
        try? save()
    }

    public func remove(id: UUID) {
        userSnippets.removeAll { $0.id == id }
        try? save()
    }

    public func save() throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(userSnippets)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Built-in seeds

    private static func bundledSnippets() -> [Snippet] {
        return [
            Snippet(
                title: "Markdown — Frontmatter",
                body: """
                ---
                title:
                date:
                tags: []
                ---

                """,
                fileType: .markdown,
                tags: ["frontmatter", "yaml"],
                isBuiltIn: true
            ),
            Snippet(
                title: "Markdown — Table",
                body: """
                | Header 1 | Header 2 | Header 3 |
                |----------|----------|----------|
                | row 1 a  | row 1 b  | row 1 c  |
                | row 2 a  | row 2 b  | row 2 c  |
                """,
                fileType: .markdown,
                tags: ["table"],
                isBuiltIn: true
            ),
            Snippet(
                title: "Markdown — Task list",
                body: """
                - [ ] First task
                - [ ] Second task
                  - [ ] Sub-task
                - [x] Done
                """,
                fileType: .markdown,
                tags: ["checklist", "todo"],
                isBuiltIn: true
            ),
            Snippet(
                title: "PlantUML — Sequence diagram",
                body: """
                @startuml
                actor User
                participant App
                participant API

                User -> App: Action
                App -> API: Request
                API --> App: Response
                App --> User: Update
                @enduml
                """,
                fileType: .plantUML,
                tags: ["sequence"],
                isBuiltIn: true
            ),
            Snippet(
                title: "PlantUML — Class diagram",
                body: """
                @startuml
                class Animal {
                  +name: String
                  +makeSound()
                }
                class Dog {
                  +breed: String
                }
                Animal <|-- Dog
                @enduml
                """,
                fileType: .plantUML,
                tags: ["class"],
                isBuiltIn: true
            ),
            Snippet(
                title: "PlantUML — Activity diagram",
                body: """
                @startuml
                start
                :Read input;
                if (valid?) then (yes)
                  :Process;
                else (no)
                  :Show error;
                  stop
                endif
                :Save;
                stop
                @enduml
                """,
                fileType: .plantUML,
                tags: ["activity", "flow"],
                isBuiltIn: true
            ),
            Snippet(
                title: "MindMap — Project plan",
                body: """
                Goals
                Milestones
                Risks
                Stakeholders
                Timeline
                """,
                fileType: .mindMap,
                tags: ["plan"],
                isBuiltIn: true
            ),
            Snippet(
                title: "MindMap — Meeting notes",
                body: """
                Attendees
                Agenda
                Decisions
                Action items
                Follow-ups
                """,
                fileType: .mindMap,
                tags: ["meeting"],
                isBuiltIn: true
            ),
        ]
    }
}
