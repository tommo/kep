import Foundation

/// Parsed model of a PlantUML sequence diagram — the output of SequenceParser
/// and input to SequenceLayout. Pure value types, Equatable for golden tests.
/// Actors are referenced by their index into `ParsedSequence.actors`.

/// The glyph at the head/foot of a lifeline.
public enum SeqHead: String, Equatable, Sendable {
    case participant, actor, boundary, control, entity, database, collections, queue
}

/// An arrowhead style at one end of a message line.
public enum ArrowHead: Equatable, Sendable {
    case none, filled, open, cross, circle
}

public enum NotePlacement: Equatable, Sendable {
    case leftOf, rightOf, over
}

public struct SeqActor: Equatable, Sendable {
    public let name: String     // display text
    public let alias: String    // referenced token (== name when no `as`)
    public let index: Int
    public let head: SeqHead
    public init(name: String, alias: String, index: Int, head: SeqHead) {
        self.name = name; self.alias = alias; self.index = index; self.head = head
    }
}

public indirect enum Signal: Equatable, Sendable {
    case message(from: Int, to: Int, dashed: Bool, leftHead: ArrowHead, rightHead: ArrowHead, text: String)
    case selfMessage(actor: Int, text: String)
    case note(placement: NotePlacement, actors: [Int], text: String)
    case activate(actor: Int)
    case deactivate(actor: Int)
    case group(kind: String, label: String, sections: [Section])
    case divider(text: String)
    case space(height: Double)
}

public struct Section: Equatable, Sendable {
    public let elseLabel: String?     // nil for the first section
    public let signals: [Signal]
    public init(elseLabel: String?, signals: [Signal]) {
        self.elseLabel = elseLabel; self.signals = signals
    }
}

public struct ParsedSequence: Equatable, Sendable {
    public let actors: [SeqActor]
    public let signals: [Signal]
    public let title: String?
    public init(actors: [SeqActor], signals: [Signal], title: String?) {
        self.actors = actors; self.signals = signals; self.title = title
    }
    public var isEmpty: Bool { actors.isEmpty && signals.isEmpty }
}
