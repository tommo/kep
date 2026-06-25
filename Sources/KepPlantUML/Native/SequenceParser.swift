import Foundation

/// Line-oriented parser for the PlantUML sequence-diagram subset. Never throws:
/// unrecognized lines are ignored (partial render beats a hard error). Pure.
public enum SequenceParser {

    public enum DiagramKind: Equatable { case sequence, other }

    /// Conservative classifier — only `.sequence` when a participant/actor decl
    /// or a message arrow is present AND no strong non-sequence cue appears.
    public static func diagramKind(source: String) -> DiagramKind {
        var sawSequenceSignal = false
        for raw in source.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("'") || line.hasPrefix("!") { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("@start") {
                // A non-uml @start (json/salt/gantt/mindmap/wbs/yaml) is not a sequence.
                if !lower.hasPrefix("@startuml") { return .other }
                continue
            }
            if lower.hasPrefix("@end") || lower.hasPrefix("skinparam") || lower.hasPrefix("hide")
                || lower.hasPrefix("show") || lower.hasPrefix("title") || lower.hasPrefix("header")
                || lower.hasPrefix("footer") || lower.hasPrefix("scale") { continue }
            // Strong non-sequence cues → other.
            for cue in ["class ", "interface ", "abstract ", "enum ", "annotation ",
                        "state ", "usecase ", "object ", "(*)", "<|--", "<|..", "*--", "o--",
                        "start", "stop", "fork", "partition", "rectangle ", "component ", "node ",
                        "json ", "salt"] where lower.hasPrefix(cue) || lower.contains(" <|-- ") {
                return .other
            }
            if isDecl(line) != nil || messageRegex.firstMatch(in: line, range: nsRange(line)) != nil {
                sawSequenceSignal = true
            }
        }
        return sawSequenceSignal ? .sequence : .other
    }

    // MARK: - Parse

    public static func parse(_ source: String) -> ParsedSequence {
        var actors: [SeqActor] = []
        var indexByKey: [String: Int] = [:]
        var title: String?

        @discardableResult
        func actorIndex(_ keyRaw: String, head: SeqHead = .participant, displayName: String? = nil) -> Int {
            let key = unquote(keyRaw)
            if let i = indexByKey[key] { return i }
            let idx = actors.count
            actors.append(SeqActor(name: displayName ?? key, alias: key, index: idx, head: head))
            indexByKey[key] = idx
            return idx
        }

        // Grouping frame builder.
        struct Frame { var kind: String; var label: String; var sections: [Section]; var currentLabel: String?; var current: [Signal] }
        var stack: [Frame] = []
        var top: [Signal] = []
        func emit(_ s: Signal) {
            if stack.isEmpty { top.append(s) } else { stack[stack.count - 1].current.append(s) }
        }

        // Note-block accumulation.
        var noteOpen: (placement: NotePlacement, actors: [Int])?
        var noteLines: [String] = []

        for rawLine in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Inside a multi-line note: accumulate until `end note`.
            if let open = noteOpen {
                if line.lowercased() == "end note" {
                    emit(.note(placement: open.placement, actors: open.actors,
                               text: noteLines.joined(separator: "\n")))
                    noteOpen = nil; noteLines = []
                } else {
                    noteLines.append(line)
                }
                continue
            }

            if line.isEmpty || line.hasPrefix("'") || line.hasPrefix("!") { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("@start") || lower.hasPrefix("@end") { continue }

            if lower.hasPrefix("title ") { title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces); continue }

            // Declarations.
            if let (head, alias, name) = isDecl(line) {
                actorIndex(alias, head: head, displayName: name)
                continue
            }

            // Grouping.
            if let kw = groupKeyword(lower) {
                let label = String(line.dropFirst(kw.count)).trimmingCharacters(in: .whitespaces)
                stack.append(Frame(kind: kw, label: label, sections: [], currentLabel: nil, current: []))
                continue
            }
            if lower == "end" || lower == "end group" {
                if var f = stack.popLast() {
                    f.sections.append(Section(elseLabel: f.currentLabel, signals: f.current))
                    emit(.group(kind: f.kind, label: f.label, sections: f.sections))
                }
                continue
            }
            if lower == "else" || lower.hasPrefix("else ") || lower == "and" || lower.hasPrefix("and ") {
                if !stack.isEmpty {
                    let label = line.contains(" ") ? String(line.drop { $0 != " " }).trimmingCharacters(in: .whitespaces) : ""
                    var f = stack[stack.count - 1]
                    f.sections.append(Section(elseLabel: f.currentLabel, signals: f.current))
                    f.currentLabel = label
                    f.current = []
                    stack[stack.count - 1] = f
                }
                continue
            }

            // Notes.
            if let note = parseNote(line, actorIndex: { actorIndex($0) }) {
                switch note {
                case .inline(let placement, let acts, let text):
                    emit(.note(placement: placement, actors: acts, text: text))
                case .blockOpen(let placement, let acts):
                    noteOpen = (placement, acts); noteLines = []
                }
                continue
            }

            // activate / deactivate.
            if lower.hasPrefix("activate ") {
                emit(.activate(actor: actorIndex(String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? "")))
                continue
            }
            if lower.hasPrefix("deactivate ") {
                emit(.deactivate(actor: actorIndex(String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces))))
                continue
            }

            // Divider  == text ==
            if line.hasPrefix("==") && line.hasSuffix("==") && line.count > 4 {
                emit(.divider(text: line.dropFirst(2).dropLast(2).trimmingCharacters(in: .whitespaces)))
                continue
            }
            if line == "|||" || line.hasPrefix("...") {
                emit(.space(height: 16)); continue
            }

            // Message (the core).
            if let m = messageRegex.firstMatch(in: line, range: nsRange(line)) {
                let left = group(m, 1, line), arrowTok = group(m, 2, line), right = group(m, 3, line)
                let suffix = group(m, 4, line), text = group(m, 5, line)
                let arrow = parseArrow(arrowTok)
                var fromKey = left, toKey = right
                var lead = arrow.leftHead, trail = arrow.rightHead
                if arrow.reversed { swap(&fromKey, &toKey); trail = arrow.leftHead; lead = .none }
                let from = actorIndex(fromKey), to = actorIndex(toKey)
                if from == to {
                    emit(.selfMessage(actor: from, text: text))
                } else {
                    emit(.message(from: from, to: to, dashed: arrow.dashed,
                                  leftHead: lead, rightHead: trail, text: text))
                }
                // Activation shorthand.
                if suffix == "++" { emit(.activate(actor: to)) }
                else if suffix == "--" { emit(.deactivate(actor: from)) }
                continue
            }
            // Unknown line → ignored.
        }
        // Close any unterminated groups defensively.
        while var f = stack.popLast() {
            f.sections.append(Section(elseLabel: f.currentLabel, signals: f.current))
            top.append(.group(kind: f.kind, label: f.label, sections: f.sections))
        }
        return ParsedSequence(actors: actors, signals: top, title: title)
    }

    // MARK: - Pieces

    static let messageRegex = try! NSRegularExpression(
        pattern: #"^\s*("[^"]+"|\w+)\s*([<>ox]{0,2}-{1,2}[<>ox\\/]{0,2})\s*("[^"]+"|\w+)\s*((?:\+\+|--|\*\*|!!))?\s*(?::\s*(.*))?$"#)

    private static let headKeywords: [String: SeqHead] = [
        "participant": .participant, "actor": .actor, "boundary": .boundary, "control": .control,
        "entity": .entity, "database": .database, "collections": .collections, "queue": .queue,
    ]
    private static let declRegex = try! NSRegularExpression(
        pattern: #"^(participant|actor|boundary|control|entity|database|collections|queue)\s+(?:("[^"]+"|\w+)\s+as\s+(\w+)|("[^"]+"|\w+))"#,
        options: [.caseInsensitive])

    /// Returns (head, alias, displayName) for a declaration line, else nil.
    static func isDecl(_ line: String) -> (SeqHead, String, String)? {
        guard let m = declRegex.firstMatch(in: line, range: nsRange(line)) else { return nil }
        let head = headKeywords[group(m, 1, line).lowercased()] ?? .participant
        if let r3 = Range(m.range(at: 3), in: line) {   // "name" as alias
            let name = unquote(group(m, 2, line))
            return (head, String(line[r3]), name)
        }
        let token = group(m, 4, line)
        let name = unquote(token)
        return (head, name, name)
    }

    private static func groupKeyword(_ lower: String) -> String? {
        for kw in ["alt", "opt", "loop", "par", "break", "critical", "group"] {
            if lower == kw || lower.hasPrefix(kw + " ") { return kw }
        }
        return nil
    }

    struct Arrow { var dashed: Bool; var leftHead: ArrowHead; var rightHead: ArrowHead; var reversed: Bool }

    static func parseArrow(_ token: String) -> Arrow {
        guard let dashRange = token.range(of: #"-{1,2}"#, options: .regularExpression) else {
            return Arrow(dashed: false, leftHead: .none, rightHead: .filled, reversed: false)
        }
        let pre = String(token[token.startIndex..<dashRange.lowerBound])
        let dashes = String(token[dashRange])
        let post = String(token[dashRange.upperBound...])
        let left = head(pre), right = head(post)
        let reversed = left != .none && right == .none
        return Arrow(dashed: dashes.count >= 2, leftHead: left, rightHead: right, reversed: reversed)
    }

    private static func head(_ s: String) -> ArrowHead {
        // The head can combine a direction char with a style (e.g. ">x", ">o",
        // ">>"); scan for the style, defaulting to a filled triangle.
        if s.isEmpty { return .none }
        if s.contains("x") { return .cross }
        if s.contains("o") { return .circle }
        if s.contains(">>") || s.contains("<<") { return .open }
        return .filled
    }

    // MARK: - Notes

    enum ParsedNote {
        case inline(NotePlacement, [Int], String)
        case blockOpen(NotePlacement, [Int])
    }
    private static func parseNote(_ line: String, actorIndex: (String) -> Int) -> ParsedNote? {
        let lower = line.lowercased()
        guard lower.hasPrefix("note ") || lower == "note" else { return nil }
        // Split off the ": text" for inline notes.
        let hasText = line.contains(":")
        let headPart = hasText ? String(line[..<line.firstIndex(of: ":")!]) : line
        let text = hasText ? String(line[line.index(after: line.firstIndex(of: ":")!)...]).trimmingCharacters(in: .whitespaces) : ""
        let hl = headPart.lowercased()
        let placement: NotePlacement
        var acts: [Int] = []
        if hl.contains("left") { placement = .leftOf }
        else if hl.contains("right") { placement = .rightOf }
        else if hl.contains("over") { placement = .over }
        else { placement = .over }
        // Extract actor tokens after "of" / "over".
        if let kw = hl.contains("over") ? "over" : (hl.contains(" of ") ? "of" : nil),
           let r = hl.range(of: kw) {
            let rest = String(headPart[headPart.index(headPart.startIndex, offsetBy: hl.distance(from: hl.startIndex, to: r.upperBound))...])
            for tok in rest.split(whereSeparator: { $0 == "," }) {
                let t = tok.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { acts.append(actorIndex(t)) }
            }
        }
        return hasText ? .inline(placement, acts, text) : .blockOpen(placement, acts)
    }

    // MARK: - Helpers

    private static func nsRange(_ s: String) -> NSRange { NSRange(s.startIndex..., in: s) }
    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String {
        guard i < m.numberOfRanges, let r = Range(m.range(at: i), in: s) else { return "" }
        return String(s[r])
    }
    private static func unquote(_ s: String) -> String {
        (s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2) ? String(s.dropFirst().dropLast()) : s
    }
}
