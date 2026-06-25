import Foundation

/// One problem found in PlantUML source by the native linter.
public struct PlantUMLDiagnostic: Equatable, Sendable {
    public enum Severity: String, Sendable { case error, warning }
    public let line: Int          // 1-based
    public let message: String
    public let severity: Severity
    public init(line: Int, message: String, severity: Severity) {
        self.line = line; self.message = message; self.severity = severity
    }
}

/// A conservative, dependency-free linter for the most common "why won't it
/// render" mistakes — unbalanced `@start/@end`, unclosed block comments, and
/// (for sequence diagrams) unmatched control blocks (`alt`/`loop`/… vs `end`).
/// Pure → unit-testable; deliberately narrow to avoid false positives that
/// would be worse than no linter. The editor surfaces these in the preview.
public enum PlantUMLDiagnostics {

    /// Sequence control-block openers that must be closed with `end`.
    private static let controlOpeners: Set<String> = [
        "alt", "opt", "loop", "par", "break", "critical", "group",
    ]

    public static func analyze(_ source: String) -> [PlantUMLDiagnostic] {
        var out: [PlantUMLDiagnostic] = []
        let rawLines = source.components(separatedBy: "\n")

        // --- Block comments /' … '/ (may span lines) + @start/@end stack. ---
        var commentOpenLine: Int?
        var startStack: [(line: Int, kind: String)] = []   // kind = "uml", "mindmap", …
        // Whether we're inside a diagram block (for control-block checks).
        var sawAnyStart = false

        // Strip a leading single-line /' … '/ region tracker per line.
        for (i, raw) in rawLines.enumerated() {
            let lineNo = i + 1
            var line = raw

            // Track block comments. If open, look for the closer; ignore content.
            if commentOpenLine != nil {
                if let r = line.range(of: "'/") {
                    line = String(line[r.upperBound...]); commentOpenLine = nil
                } else {
                    continue
                }
            }
            // Remove any complete /' … '/ on this line, then detect a dangling open.
            while let open = line.range(of: "/'") {
                if let close = line.range(of: "'/", range: open.upperBound..<line.endIndex) {
                    line.removeSubrange(open.lowerBound..<close.upperBound)
                } else {
                    commentOpenLine = lineNo
                    line = String(line[..<open.lowerBound])
                    break
                }
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            // Skip single-line comments.
            if trimmed.hasPrefix("'") { continue }

            let firstToken = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? ""
            let lower = firstToken.lowercased()

            if lower.hasPrefix("@start") {
                startStack.append((lineNo, String(lower.dropFirst("@start".count))))
                sawAnyStart = true
            } else if lower.hasPrefix("@end") {
                let kind = String(lower.dropFirst("@end".count))
                if let top = startStack.popLast() {
                    if !top.kind.isEmpty, !kind.isEmpty, top.kind != kind {
                        out.append(.init(line: lineNo,
                                         message: "@end\(kind) does not match @start\(top.kind) on line \(top.line)",
                                         severity: .error))
                    }
                } else {
                    out.append(.init(line: lineNo, message: "@end\(kind) without a matching @start\(kind)", severity: .error))
                }
            }
        }

        if let open = commentOpenLine {
            out.append(.init(line: open, message: "unterminated block comment — missing `'/`", severity: .error))
        }
        for unclosed in startStack {
            out.append(.init(line: unclosed.line,
                             message: "@start\(unclosed.kind) is never closed with @end\(unclosed.kind)",
                             severity: .error))
        }

        out.append(contentsOf: controlBlockDiagnostics(source, sawAnyStart: sawAnyStart))
        return out.sorted { $0.line < $1.line }
    }

    /// Balance of sequence control blocks (`alt`/`opt`/`loop`/… ↔ `end`). Only
    /// runs for sequence diagrams, where these keywords are unambiguous.
    private static func controlBlockDiagnostics(_ source: String, sawAnyStart: Bool) -> [PlantUMLDiagnostic] {
        guard SequenceParser.diagramKind(source: source) == .sequence else { return [] }
        var out: [PlantUMLDiagnostic] = []
        var stack: [(line: Int, kind: String)] = []
        var inComment = false

        for (i, raw) in source.components(separatedBy: "\n").enumerated() {
            let lineNo = i + 1
            var line = raw
            if inComment { if let r = line.range(of: "'/") { line = String(line[r.upperBound...]); inComment = false } else { continue } }
            while let open = line.range(of: "/'") {
                if let close = line.range(of: "'/", range: open.upperBound..<line.endIndex) {
                    line.removeSubrange(open.lowerBound..<close.upperBound)
                } else { inComment = true; line = String(line[..<open.lowerBound]); break }
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("'") { continue }
            let token = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map { $0.lowercased() } ?? ""

            if controlOpeners.contains(token) {
                stack.append((lineNo, token))
            } else if token == "end" {
                if stack.popLast() == nil {
                    out.append(.init(line: lineNo, message: "`end` without a matching alt/opt/loop/par/group", severity: .error))
                }
            }
        }
        for open in stack {
            out.append(.init(line: open.line, message: "`\(open.kind)` block is never closed with `end`", severity: .error))
        }
        return out
    }
}
