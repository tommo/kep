import XCTest
@testable import KepPlantUML

final class PlantUMLSourceTests: XCTestCase {

    private func substr(_ s: String, _ r: NSRange?) -> String? {
        guard let r else { return nil }
        return (s as NSString).substring(with: r)
    }

    func testWholeWordMatch() {
        let src = "@startuml\nAlice -> Bob: hi\n@enduml"
        let r = PlantUMLSource.firstRange(ofEntity: "Bob", in: src)
        XCTAssertEqual(substr(src, r), "Bob")
        // Not a substring of "Alice" etc. — first standalone Bob.
        XCTAssertEqual(r?.location, (src as NSString).range(of: "Bob").location)
    }

    func testPrefersQuotedAliasDeclaration() {
        // "Bob Server" is the display name; it appears quoted on the participant
        // line and must be found there (not as a bare word elsewhere).
        let src = "participant \"Bob Server\" as Bob\nAlice -> Bob: hi"
        let r = PlantUMLSource.firstRange(ofEntity: "Bob Server", in: src)
        XCTAssertEqual(substr(src, r), "\"Bob Server\"")
    }

    func testWholeWordPreferredOverLongerToken() {
        // "Bob" must match the standalone Bob, not the "Bob" inside "Bobby".
        let src = "note over Bobby\nAlice -> Bob: hi"
        let r = PlantUMLSource.firstRange(ofEntity: "Bob", in: src)
        XCTAssertEqual(r?.location, (src as NSString).range(of: "Bob:").location)
    }

    func testMissingEntityReturnsNil() {
        XCTAssertNil(PlantUMLSource.firstRange(ofEntity: "Zork", in: "Alice -> Bob"))
        XCTAssertNil(PlantUMLSource.firstRange(ofEntity: "", in: "Alice -> Bob"))
    }
}
