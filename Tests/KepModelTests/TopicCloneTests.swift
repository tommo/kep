import XCTest
@testable import KepModel

final class TopicCloneTests: XCTestCase {

    func testShallowCloneCopiesTextAndAttributes() {
        let t = Topic(text: "Source")
        t.setAttribute(TopicAttribute.fillColor, "#FF0000")
        t.setAttribute(TopicAttribute.collapsed, "true")

        let clone = t.clone(deep: false)
        XCTAssertEqual(clone.text, "Source")
        XCTAssertEqual(clone.attribute(TopicAttribute.fillColor), "#FF0000")
        XCTAssertEqual(clone.attribute(TopicAttribute.collapsed), "true")
        XCTAssertNil(clone.parent, "fresh clone has no parent until appended")
        XCTAssertTrue(clone.children.isEmpty, "shallow clone drops children")
    }

    func testShallowCloneDropsChildren() {
        let t = Topic(text: "Parent")
        _ = t.addChild(text: "A")
        _ = t.addChild(text: "B")
        let clone = t.clone(deep: false)
        XCTAssertEqual(clone.children.count, 0)
    }

    func testDeepCloneRecursivelyCopiesSubtree() {
        let t = Topic(text: "Parent")
        let a = t.addChild(text: "A")
        _ = a.addChild(text: "A1")
        _ = t.addChild(text: "B")

        let clone = t.clone(deep: true)
        XCTAssertEqual(clone.children.count, 2)
        XCTAssertEqual(clone.children[0].text, "A")
        XCTAssertEqual(clone.children[0].children.count, 1)
        XCTAssertEqual(clone.children[0].children[0].text, "A1")
        XCTAssertEqual(clone.children[1].text, "B")
    }

    func testDeepCloneChildrenAreIndependent() {
        let t = Topic(text: "Parent")
        let original = t.addChild(text: "A")
        let clone = t.clone(deep: true)
        // Mutate original — clone's child must not budge.
        original.text = "Mutated"
        XCTAssertEqual(clone.children[0].text, "A")
    }

    func testCloneSharesImmutableExtraInstances() {
        // Built-in Extras are immutable (`let` fields), so sharing the same
        // Extra reference between source and clone is safe and saves work.
        let t = Topic(text: "Parent")
        t.setExtra(ExtraLink(uri: "https://example.com"))
        let clone = t.clone(deep: false)
        XCTAssertTrue(clone.extra(.link) === t.extra(.link),
                      "immutable Extras can share identity; clone should not deep-copy them")
    }

    func testClonedExtraOverwriteDoesNotAffectSource() {
        let t = Topic(text: "Parent")
        t.setExtra(ExtraLink(uri: "https://a"))
        let clone = t.clone(deep: false)
        clone.setExtra(ExtraLink(uri: "https://b"))
        XCTAssertEqual((t.extra(.link) as? ExtraLink)?.uri, "https://a")
        XCTAssertEqual((clone.extra(.link) as? ExtraLink)?.uri, "https://b")
    }
}
