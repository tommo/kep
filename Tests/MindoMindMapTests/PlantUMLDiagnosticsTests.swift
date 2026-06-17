import XCTest
@testable import MindoPlantUML

final class PlantUMLDiagnosticsTests: XCTestCase {

    private func errors(_ s: String) -> [PlantUMLDiagnostic] {
        PlantUMLDiagnostics.analyze(s).filter { $0.severity == .error }
    }

    func testCleanSequenceHasNoDiagnostics() {
        let s = """
        @startuml
        alt success
          Alice -> Bob: hi
        else failure
          Alice -> Bob: bye
        end
        @enduml
        """
        XCTAssertTrue(PlantUMLDiagnostics.analyze(s).isEmpty)
    }

    func testMissingEnduml() {
        let d = errors("@startuml\nAlice -> Bob: hi\n")
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d.first?.line, 1)
        XCTAssertTrue(d.first!.message.contains("never closed"))
    }

    func testStrayEnduml() {
        let d = errors("Alice -> Bob: hi\n@enduml")
        XCTAssertEqual(d.count, 1)
        XCTAssertEqual(d.first?.line, 2)
        XCTAssertTrue(d.first!.message.contains("without a matching"))
    }

    func testMismatchedStartEnd() {
        let d = errors("@startuml\n@endmindmap")
        XCTAssertTrue(d.contains { $0.message.contains("does not match") })
    }

    func testUnterminatedBlockComment() {
        let d = errors("@startuml\n/' open comment\nAlice -> Bob: hi\n@enduml")
        XCTAssertTrue(d.contains { $0.message.contains("unterminated block comment") && $0.line == 2 })
    }

    func testClosedBlockCommentIsFine() {
        let s = "@startuml\n/' a comment '/\nAlice -> Bob: hi\n@enduml"
        XCTAssertTrue(PlantUMLDiagnostics.analyze(s).isEmpty)
    }

    func testUnmatchedAltBlock() {
        let d = errors("@startuml\nalt ok\n  A -> B: x\n@enduml")
        XCTAssertTrue(d.contains { $0.message.contains("never closed with `end`") && $0.line == 2 })
    }

    func testStrayEndBlock() {
        let d = errors("@startuml\nA -> B: x\nend\n@enduml")
        XCTAssertTrue(d.contains { $0.message.contains("without a matching alt") })
    }

    func testControlBlockCheckOnlyForSequence() {
        // A class diagram with `end`-less braces must not trip the control-block check.
        let s = """
        @startuml
        class Foo {
          +bar()
        }
        @enduml
        """
        XCTAssertTrue(PlantUMLDiagnostics.analyze(s).isEmpty)
    }

    func testKeywordInMessageTextIgnored() {
        // "end" / "alt" only count as the FIRST token, not inside message text.
        let s = "@startuml\nA -> B: the end\nA -> B: alt route\n@enduml"
        XCTAssertTrue(PlantUMLDiagnostics.analyze(s).isEmpty)
    }
}
