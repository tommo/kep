import Foundation
import KepModel

// G2 — Document editing (disk writes). All writes go through writeDocument(...)
// so effects (changed/created files) are recorded.
extension KepAgentTools {
    static let docEditDescriptors: [(name: String, description: String, parametersJSON: String)] = [
        ("create_document", "Create a new workspace document. Fails if a document of that name already exists (use overwrite_document).",
         #"{"type":"object","properties":{"name":{"type":"string"},"type":{"type":"string","enum":["md","mmd","puml","csv","txt"]},"content":{"type":"string"}},"required":["name"]}"#),
        ("overwrite_document", "Replace the entire contents of a workspace document, creating it (as .md) if it doesn't exist.",
         #"{"type":"object","properties":{"name":{"type":"string"},"content":{"type":"string"}},"required":["name","content"]}"#),
        ("append_to_document", "Append text to the end of a workspace document, creating it (as .md) if it doesn't exist.",
         #"{"type":"object","properties":{"name":{"type":"string"},"content":{"type":"string"}},"required":["name","content"]}"#),
        ("replace_section", "In a Markdown document, replace the body under the first heading matching `heading` (keeping the heading line) up to the next same-or-higher-level heading.",
         #"{"type":"object","properties":{"name":{"type":"string"},"heading":{"type":"string"},"content":{"type":"string"}},"required":["name","heading","content"]}"#),
        ("insert_after_heading", "In a Markdown document, insert content immediately after the first heading line matching `heading` (before its existing body).",
         #"{"type":"object","properties":{"name":{"type":"string"},"heading":{"type":"string"},"content":{"type":"string"}},"required":["name","heading","content"]}"#),
    ]

    func handleDocEdit(_ name: String, _ a: ToolArgs) -> String? {
        switch name {
        case "create_document":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            if let e = ambiguityError(forWriteName: docName) { return e }
            if documentURL(named: docName) != nil {
                return "error: \(docName) already exists (use overwrite_document)"
            }
            let ext = Self.docExt(a.str("type"))
            guard let url = resolveOrCreateURL(name: docName, ext: ext) else {
                return "error: no workspace folder to create in"
            }
            // A .mmd is a structured mind-map format, not free text — writing
            // arbitrary content yields an unparseable file. Seed valid .mmd: a
            // root named after the doc, with any content lines as child topics.
            let body = ext == "mmd"
                ? Self.seedMindMap(name: docName, content: a.str("content"))
                : (a.str("content") ?? "")
            return writeDocument(url, body, created: true)

        case "overwrite_document":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            guard let content = a.str("content") else { return "error: missing 'content'" }
            if let e = ambiguityError(forWriteName: docName) { return e }
            let existing = documentURL(named: docName)
            guard let url = existing ?? resolveOrCreateURL(name: docName, ext: "md") else {
                return "error: no workspace folder to create in"
            }
            return writeDocument(url, content, created: existing == nil)

        case "append_to_document":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            guard let content = a.str("content") else { return "error: missing 'content'" }
            if let e = ambiguityError(forWriteName: docName) { return e }
            let existing = documentText(named: docName)
            let body = (existing ?? "") + ((existing?.isEmpty == false) ? "\n" : "") + content
            guard let url = documentURL(named: docName) ?? resolveOrCreateURL(name: docName, ext: "md") else {
                return "error: no workspace folder to create in"
            }
            return writeDocument(url, body, created: existing == nil)

        case "replace_section":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            guard let heading = a.str("heading") else { return "error: missing 'heading'" }
            guard let content = a.str("content") else { return "error: missing 'content'" }
            guard let text = documentText(named: docName) else { return "error: \(docName) not found" }
            if let e = ambiguityError(forWriteName: docName) { return e }
            guard let updated = Self.replaceSection(in: text, heading: heading, with: content) else {
                return "error: heading not found"
            }
            guard let url = documentURL(named: docName) ?? resolveOrCreateURL(name: docName, ext: "md") else {
                return "error: no workspace folder to create in"
            }
            return writeDocument(url, updated, created: false)

        case "insert_after_heading":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            guard let heading = a.str("heading") else { return "error: missing 'heading'" }
            guard let content = a.str("content") else { return "error: missing 'content'" }
            guard let text = documentText(named: docName) else { return "error: \(docName) not found" }
            if let e = ambiguityError(forWriteName: docName) { return e }
            guard let updated = Self.insertAfterHeading(in: text, heading: heading, with: content) else {
                return "error: heading not found"
            }
            guard let url = documentURL(named: docName) ?? resolveOrCreateURL(name: docName, ext: "md") else {
                return "error: no workspace folder to create in"
            }
            return writeDocument(url, updated, created: false)

        default:
            return nil
        }
    }

    // MARK: - Markdown helpers (file-scoped)

    /// Normalise a requested document type to a supported extension (default md).
    fileprivate static func docExt(_ type: String?) -> String {
        switch type?.lowercased() {
        case "md", "mmd", "puml", "csv", "txt": return type!.lowercased()
        default: return "md"
        }
    }

    /// Valid `.mmd` text for a new mind map: root = `name`, content lines (if
    /// any) become child topics. Avoids writing unparseable free text as .mmd.
    fileprivate static func seedMindMap(name: String, content: String?) -> String {
        let map = MindMap()
        let root = Topic(text: name)
        for line in (content ?? "").split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty { _ = root.addChild(text: t) }
        }
        map.root = root
        return map.write()
    }

    /// Parse an ATX heading line: returns (level, title) or nil for non-headings.
    fileprivate static func atxHeading(_ line: String) -> (level: Int, title: String)? {
        var hashes = 0
        for ch in line {
            if ch == "#" { hashes += 1 } else { break }
        }
        guard hashes >= 1, hashes <= 6 else { return nil }
        let rest = String(line.dropFirst(hashes))
        // A valid ATX heading requires a space (or end of line) after the hashes.
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        let title = rest.trimmingCharacters(in: .whitespaces)
        return (hashes, title)
    }

    /// Index of the first line that is an ATX heading whose title matches
    /// `heading` (case-insensitive). Returns (lineIndex, level) or nil.
    fileprivate static func findHeading(_ lines: [String], _ heading: String) -> (index: Int, level: Int)? {
        let needle = heading.trimmingCharacters(in: .whitespaces).lowercased()
        for (i, line) in lines.enumerated() {
            if let h = atxHeading(line), h.title.lowercased() == needle {
                return (i, h.level)
            }
        }
        return nil
    }

    /// Replace the body between the matching heading and the next same-or-higher
    /// level heading with `content`. Keeps the heading line. nil if not found.
    fileprivate static func replaceSection(in text: String, heading: String, with content: String) -> String? {
        var lines = splitLines(text)
        guard let found = findHeading(lines, heading) else { return nil }
        // Find the end of the section: next heading of level <= found.level.
        var end = lines.count
        var i = found.index + 1
        while i < lines.count {
            if let h = atxHeading(lines[i]), h.level <= found.level {
                end = i
                break
            }
            i += 1
        }
        let contentLines = content.isEmpty ? [] : splitLines(content)
        lines.replaceSubrange((found.index + 1)..<end, with: contentLines)
        return joinLines(lines)
    }

    /// Insert `content` immediately after the matching heading line. nil if not found.
    fileprivate static func insertAfterHeading(in text: String, heading: String, with content: String) -> String? {
        var lines = splitLines(text)
        guard let found = findHeading(lines, heading) else { return nil }
        let contentLines = content.isEmpty ? [] : splitLines(content)
        lines.insert(contentsOf: contentLines, at: found.index + 1)
        return joinLines(lines)
    }

    /// Split text into lines, preserving a trailing-newline marker so round-trips
    /// don't drop or add a final newline.
    fileprivate static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: "\n")
    }

    fileprivate static func joinLines(_ lines: [String]) -> String {
        lines.joined(separator: "\n")
    }
}
