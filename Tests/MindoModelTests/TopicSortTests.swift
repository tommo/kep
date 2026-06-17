import XCTest
@testable import MindoModel

final class TopicSortTests: XCTestCase {

    private func root(_ children: [String]) -> Topic {
        let r = Topic(text: "Root")
        for c in children { _ = r.addChild(text: c) }
        return r
    }

    func testSortAscendingCaseInsensitive() {
        let r = root(["banana", "Apple", "cherry", "apricot"])
        r.sortChildren()
        XCTAssertEqual(r.children.map(\.text), ["Apple", "apricot", "banana", "cherry"])
    }

    func testSortDescending() {
        let r = root(["b", "a", "c"])
        r.sortChildren(ascending: false)
        XCTAssertEqual(r.children.map(\.text), ["c", "b", "a"])
    }

    func testRecursiveSortsSubtree() {
        let r = Topic(text: "Root")
        let mid = r.addChild(text: "M")
        _ = mid.addChild(text: "z"); _ = mid.addChild(text: "a")
        _ = r.addChild(text: "A")
        r.sortChildren(recursive: true)
        XCTAssertEqual(r.children.map(\.text), ["A", "M"])
        XCTAssertEqual(r.children.last?.children.map(\.text), ["a", "z"])
    }

    func testNonRecursiveLeavesGrandchildren() {
        let r = Topic(text: "Root")
        let mid = r.addChild(text: "M")
        _ = mid.addChild(text: "z"); _ = mid.addChild(text: "a")
        r.sortChildren()   // not recursive
        XCTAssertEqual(mid.children.map(\.text), ["z", "a"])   // untouched
    }

    func testReorderChildrenAcceptsPermutationOnly() {
        let r = root(["a", "b", "c"])
        let kids = r.children
        r.reorderChildren([kids[2], kids[0], kids[1]])
        XCTAssertEqual(r.children.map(\.text), ["c", "a", "b"])
        // Wrong count → no-op.
        r.reorderChildren([kids[0]])
        XCTAssertEqual(r.children.map(\.text), ["c", "a", "b"])
        // Foreign element → no-op.
        r.reorderChildren([kids[0], kids[1], Topic(text: "x")])
        XCTAssertEqual(r.children.map(\.text), ["c", "a", "b"])
    }
}
