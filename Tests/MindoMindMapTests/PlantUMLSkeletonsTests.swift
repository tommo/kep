import XCTest
import MindoPlantUML

final class PlantUMLSkeletonsTests: XCTestCase {

    func testEverySkeletonOpensAndClosesItsBlock() {
        // The renderer chokes if a skeleton starts with @startxxx but
        // doesn't terminate with the matching @endxxx.
        let pairs: [(String, String, String)] = [
            ("sequence", PlantUMLSkeletons.sequence, "@startuml"),
            ("class",    PlantUMLSkeletons.classDiagram, "@startuml"),
            ("activity", PlantUMLSkeletons.activity, "@startuml"),
            ("state",    PlantUMLSkeletons.state, "@startuml"),
            ("useCase",  PlantUMLSkeletons.useCase, "@startuml"),
            ("mindMap",  PlantUMLSkeletons.mindMap, "@startmindmap"),
        ]
        for (label, body, openTag) in pairs {
            XCTAssertTrue(body.hasPrefix(openTag), "\(label) missing \(openTag) prefix")
            let closer = openTag.replacingOccurrences(of: "@start", with: "@end")
            XCTAssertTrue(body.contains(closer), "\(label) missing \(closer)")
        }
    }

    func testSequenceSkeletonHasArrowsBetweenParticipants() {
        let body = PlantUMLSkeletons.sequence
        XCTAssertTrue(body.contains("User -> App"))
        XCTAssertTrue(body.contains("App -> API"))
    }

    func testClassDiagramHasInheritance() {
        XCTAssertTrue(PlantUMLSkeletons.classDiagram.contains("<|--"))
    }

    func testStateDiagramStartsAtInitialState() {
        XCTAssertTrue(PlantUMLSkeletons.state.contains("[*] -->"))
    }

    func testMindMapUsesAsteriskNesting() {
        XCTAssertTrue(PlantUMLSkeletons.mindMap.contains("** Branch A"))
    }
}
