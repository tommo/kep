import XCTest
@testable import KepModel

final class AncestorsToRootTests: XCTestCase {
    func testRouteFromLeafToRoot() {
        let root = Topic(text: "Root")
        let a = root.addChild(text: "A")
        let b = a.addChild(text: "B")        // root → A → B
        let route = b.ancestorsToRoot
        XCTAssertEqual(route.map(\.text), ["B", "A", "Root"])   // self first, root last
        // The path set used for highlighting includes the node + all ancestors.
        let ids = Set(route.map(ObjectIdentifier.init))
        XCTAssertTrue(ids.contains(ObjectIdentifier(a)))
        XCTAssertTrue(ids.contains(ObjectIdentifier(root)))
        XCTAssertFalse(ids.contains(ObjectIdentifier(root.addChild(text: "C"))))  // sibling off-path
    }

    func testRootRouteIsJustItself() {
        let root = Topic(text: "Root")
        XCTAssertEqual(root.ancestorsToRoot.map(\.text), ["Root"])
    }
}
