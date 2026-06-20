import XCTest
import AppKit
import MindoModel
@testable import MindoMindMap

/// "Copy Text" copies only the node's own text — not the subtree blob ⌘C
/// produces (#177).
@MainActor
final class CopyNodeTextTests: XCTestCase {

    func testCopiesOnlyOwnTextNotSubtree() {
        let root = Topic(text: "Parent")
        root.addChild(text: "Child A")
        root.addChild(text: "Child B")

        let pb = NSPasteboard(name: NSPasteboard.Name("mindo.test.copytext"))
        let copied = MindMapView.copyPlainText(of: root, to: pb)

        XCTAssertEqual(copied, "Parent")
        XCTAssertEqual(pb.string(forType: .string), "Parent")
        XCTAssertFalse(pb.string(forType: .string)?.contains("Child") ?? true,
                       "must not include any child text")
    }

    func testPreservesMultilineAndUnicode() {
        let t = Topic(text: "line one\nlíne twö 日本語")
        let pb = NSPasteboard(name: NSPasteboard.Name("mindo.test.copytext2"))
        MindMapView.copyPlainText(of: t, to: pb)
        XCTAssertEqual(pb.string(forType: .string), "line one\nlíne twö 日本語")
    }
}
