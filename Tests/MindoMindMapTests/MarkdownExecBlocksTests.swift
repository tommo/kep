import XCTest
@testable import MindoMarkdown

final class MarkdownExecBlocksTests: XCTestCase {

    func testParsesExecBlockWithExplicitId() {
        let md = """
        # Notes

        ```lua {exec id=trend}
        return 1 + 2
        ```

        done
        """
        let blocks = MarkdownExecBlocks.parse(md)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].id, "trend")
        XCTAssertEqual(blocks[0].language, "lua")
        XCTAssertEqual(blocks[0].code, "return 1 + 2")
    }

    func testAutoIdsAndOnlyExecBlocks() {
        let md = """
        ```lua {exec}
        return 1
        ```
        ```lua
        -- not executable, no {exec}
        return 2
        ```
        ```swift {exec}
        let x = 3
        ```
        """
        let blocks = MarkdownExecBlocks.parse(md)
        XCTAssertEqual(blocks.map(\.id), ["cell-1", "cell-2"])
        XCTAssertEqual(blocks.map(\.language), ["lua", "swift"])
    }

    func testHashChangesWithCode() {
        let a = MarkdownExecBlocks.parse("```lua {exec}\nreturn 1\n```")[0]
        let b = MarkdownExecBlocks.parse("```lua {exec}\nreturn 2\n```")[0]
        XCTAssertNotEqual(a.hash, b.hash)
        // Same code → same hash (stable cache key).
        let a2 = MarkdownExecBlocks.parse("```lua {exec}\nreturn 1\n```")[0]
        XCTAssertEqual(a.hash, a2.hash)
    }

    func testIgnoresNonFenceAndUnclosed() {
        XCTAssertTrue(MarkdownExecBlocks.parse("just text\n`inline {exec}`").isEmpty)
        // Unclosed fence still captures to EOF.
        let blocks = MarkdownExecBlocks.parse("```lua {exec}\nreturn 1")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].code, "return 1")
    }

    func testOutputsSidecarRoundTripAndPrune() throws {
        var outs = ExecOutputs()
        outs.set(ExecOutput(text: "3"), forHash: "aaa")
        outs.set(ExecOutput(text: "", error: "boom"), forHash: "bbb")
        let data = try JSONEncoder().encode(outs)
        let back = try JSONDecoder().decode(ExecOutputs.self, from: data)
        XCTAssertEqual(back.output(forHash: "aaa")?.text, "3")
        XCTAssertEqual(back.output(forHash: "bbb")?.error, "boom")
        var pruned = back
        pruned.prune(keeping: ["aaa"])
        XCTAssertNil(pruned.output(forHash: "bbb"))
        XCTAssertNotNil(pruned.output(forHash: "aaa"))
    }

    func testSidecarURLIsHidden() {
        let url = URL(fileURLWithPath: "/ws/research.md")
        XCTAssertEqual(ExecOutputsStore.sidecarURL(for: url).lastPathComponent, ".research.md.outputs.json")
    }
}
