import XCTest
@testable import MindoCore

final class NodePathClipboardTests: XCTestCase {

    private func file(_ path: String) -> NodeData {
        NodeData(nodeType: .file, url: URL(fileURLWithPath: path))
    }

    func testAbsoluteIsTheFullPath() {
        let node = file("/Users/x/vault/notes/todo.md")
        XCTAssertEqual(NodePathClipboard.text(for: node, kind: .absolute),
                       "/Users/x/vault/notes/todo.md")
    }

    func testRelativeStripsWorkspaceRoot() {
        let ws = NodeData(workspace: "vault", url: URL(fileURLWithPath: "/Users/x/vault"))
        let node = file("/Users/x/vault/notes/todo.md")
        node.workspace = ws
        XCTAssertEqual(NodePathClipboard.text(for: node, kind: .relative),
                       "notes/todo.md")
    }

    func testRelativeFallsBackToLastComponentWithoutWorkspace() {
        let node = file("/Users/x/vault/notes/todo.md")
        XCTAssertEqual(NodePathClipboard.text(for: node, kind: .relative),
                       "todo.md")
    }

    func testRelativeFallsBackToFullPathWhenOutsideWorkspace() {
        let ws = NodeData(workspace: "vault", url: URL(fileURLWithPath: "/Users/x/vault"))
        let node = file("/tmp/elsewhere/todo.md")
        node.workspace = ws
        XCTAssertEqual(NodePathClipboard.text(for: node, kind: .relative),
                       "/tmp/elsewhere/todo.md")
    }
}
