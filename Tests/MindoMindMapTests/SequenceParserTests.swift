import XCTest
@testable import MindoPlantUML

final class SequenceParserTests: XCTestCase {

    // MARK: - Classifier

    func testClassifierSequenceVsOther() {
        let seq = PlantUMLCatalog.snippets.first { $0.title == "Sequence" }!.body
        XCTAssertEqual(SequenceParser.diagramKind(source: seq), .sequence)
        for title in ["Class", "State", "Activity", "JSON", "Gantt", "Mindmap"] {
            let body = PlantUMLCatalog.snippets.first { $0.title == title }!.body
            XCTAssertEqual(SequenceParser.diagramKind(source: body), .other, "\(title) should fall through")
        }
    }

    func testClassifierBareMessageIsSequence() {
        XCTAssertEqual(SequenceParser.diagramKind(source: "@startuml\nAlice -> Bob: hi\n@enduml"), .sequence)
    }

    // MARK: - Parse

    func testParseCatalogSequenceSnippet() {
        let body = PlantUMLCatalog.snippets.first { $0.title == "Sequence" }!.body
        let p = SequenceParser.parse(body)
        XCTAssertEqual(p.actors.map(\.name), ["Alice", "Bob"])
        // message, activate, message, deactivate, group
        XCTAssertEqual(p.signals.count, 5)
        guard case .group(let kind, let label, let sections) = p.signals.last else {
            return XCTFail("last signal should be the alt group")
        }
        XCTAssertEqual(kind, "alt")
        XCTAssertEqual(label, "success")
        XCTAssertEqual(sections.count, 2)
        XCTAssertNil(sections[0].elseLabel)
        XCTAssertEqual(sections[1].elseLabel, "failure")
    }

    func testAliasAndAutoCreateOrder() {
        let p = SequenceParser.parse("""
        @startuml
        participant "Display Name" as A
        A -> Bob: hi
        @enduml
        """)
        XCTAssertEqual(p.actors.count, 2)
        XCTAssertEqual(p.actors[0].alias, "A")
        XCTAssertEqual(p.actors[0].name, "Display Name")
        XCTAssertEqual(p.actors[1].alias, "Bob")   // auto-created on first mention
    }

    func testActorKeywordHead() {
        let p = SequenceParser.parse("@startuml\nactor User\nUser -> Sys: go\n@enduml")
        XCTAssertEqual(p.actors[0].head, .actor)
    }

    func testSelfMessage() {
        let p = SequenceParser.parse("@startuml\nAlice -> Alice: think\n@enduml")
        XCTAssertEqual(p.actors.count, 1)
        guard case .selfMessage(let a, let t) = p.signals.first else { return XCTFail() }
        XCTAssertEqual(a, 0); XCTAssertEqual(t, "think")
    }

    func testActivationShorthand() {
        let p = SequenceParser.parse("@startuml\nA -> B ++: go\nB --> A --: done\n@enduml")
        // msg, activate(B), msg, deactivate(A)
        XCTAssertEqual(p.signals.count, 4)
        guard case .activate(let b) = p.signals[1] else { return XCTFail("activate") }
        XCTAssertEqual(p.actors[b].alias, "B")
        guard case .deactivate = p.signals[3] else { return XCTFail("deactivate") }
    }

    func testRobustToUnknownLines() {
        let p = SequenceParser.parse("""
        @startuml
        skinparam monochrome true
        !include foo.iuml
        /' a comment '/
        title My Diagram
        Alice -> Bob: hi
        hide footbox
        @enduml
        """)
        XCTAssertEqual(p.title, "My Diagram")
        XCTAssertEqual(p.signals.count, 1)   // only the message
        XCTAssertEqual(p.actors.count, 2)
    }

    func testNestedGroups() {
        let p = SequenceParser.parse("""
        @startuml
        loop 3 times
          alt ok
            A -> B: x
          else no
            A -> B: y
          end
        end
        @enduml
        """)
        guard case .group(let kind, _, let sections) = p.signals.first else { return XCTFail("loop") }
        XCTAssertEqual(kind, "loop")
        guard case .group(let inner, _, let innerSections) = sections[0].signals.first else { return XCTFail("nested alt") }
        XCTAssertEqual(inner, "alt")
        XCTAssertEqual(innerSections.count, 2)
    }

    // MARK: - Arrow re-parser

    func testArrowTable() {
        func a(_ t: String) -> SequenceParser.Arrow { SequenceParser.parseArrow(t) }
        XCTAssertEqual(a("->").dashed, false);  XCTAssertEqual(a("->").rightHead, .filled)
        XCTAssertEqual(a("-->").dashed, true);  XCTAssertEqual(a("-->").rightHead, .filled)
        XCTAssertEqual(a("->>").rightHead, .open)
        XCTAssertEqual(a("->x").rightHead, .cross)
        XCTAssertEqual(a("->o").rightHead, .circle)
        XCTAssertTrue(a("<-").reversed)
        XCTAssertEqual(a("<->").leftHead, .filled); XCTAssertEqual(a("<->").rightHead, .filled)
        XCTAssertFalse(a("<->").reversed)
    }

    func testReverseArrowSwapsEndpoints() {
        let p = SequenceParser.parse("@startuml\nBob <- Alice: reply\n@enduml")
        guard case .message(let from, let to, _, _, let right, _) = p.signals.first else { return XCTFail() }
        // Bob <- Alice means Alice → Bob.
        XCTAssertEqual(p.actors[from].alias, "Alice")
        XCTAssertEqual(p.actors[to].alias, "Bob")
        XCTAssertEqual(right, .filled)
    }
}
