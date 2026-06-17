import XCTest
import LuaSwift
import MindoModel
@testable import MindoScript

final class MindoLuaAPITests: XCTestCase {

    private func run(_ script: String, map: MindMap,
                     corpus: [(url: URL, text: String)] = [], allFiles: [URL] = []) throws -> LuaValue {
        let api = MindoLuaAPI(map: map, corpus: corpus, allFiles: allFiles)
        let engine = try LuaScriptEngine()
        try api.install(on: engine)
        return try engine.run(script)
    }

    func testBuildTree() throws {
        let map = MindMap(root: Topic(text: "Espresso"))
        _ = try run("""
            local r = mindo.root()
            local eq = mindo.addChild(r, "Equipment")
            mindo.addChild(eq, "Grinder")
            mindo.addChild(eq, "Machine")
            mindo.addChild(r, "Variables")
            """, map: map)
        let root = map.root!
        XCTAssertEqual(root.children.map(\.text), ["Equipment", "Variables"])
        XCTAssertEqual(root.children[0].children.map(\.text), ["Grinder", "Machine"])
    }

    func testReadTextDepthCount() throws {
        let map = MindMap(root: Topic(text: "Root"))
        let r = try run("""
            local r = mindo.root()
            local a = mindo.addChild(r, "A")
            mindo.addChild(a, "B")
            -- numbers are floats in the bridge; floor for a clean integer string
            return mindo.text(r) .. "/" .. math.floor(mindo.count(r)) .. "/" .. math.floor(mindo.depth(a))
            """, map: map)
        XCTAssertEqual(r.stringValue, "Root/1/1")
    }

    func testSetTextAndAttributes() throws {
        let map = MindMap(root: Topic(text: "Root"))
        _ = try run("""
            local r = mindo.root()
            mindo.setText(r, "Renamed")
            mindo.setAttr(r, "fillColor", "#ffcdd2")
            """, map: map)
        XCTAssertEqual(map.root?.text, "Renamed")
        XCTAssertEqual(map.root?.attribute("fillColor"), "#ffcdd2")
    }

    func testBatchEditViaLoop() throws {
        // The headline batch-edit use case, in real Lua.
        let map = MindMap(root: Topic(text: "Root"))
        let r = map.root!
        _ = r.addChild(text: "TODO buy beans")
        _ = r.addChild(text: "done")
        _ = r.addChild(text: "TODO dial in")
        _ = try run("""
            local r = mindo.root()
            for _, id in ipairs(mindo.children(r)) do
              if string.find(mindo.text(id), "TODO") then
                mindo.setAttr(id, "fillColor", "#ffcdd2")
              end
            end
            """, map: map)
        let colored = r.children.filter { $0.attribute("fillColor") == "#ffcdd2" }.map(\.text)
        XCTAssertEqual(Set(colored), ["TODO buy beans", "TODO dial in"])
    }

    func testRemove() throws {
        let map = MindMap(root: Topic(text: "Root"))
        let r = map.root!
        _ = r.addChild(text: "keep")
        _ = r.addChild(text: "drop")
        _ = try run("""
            local r = mindo.root()
            for _, id in ipairs(mindo.children(r)) do
              if mindo.text(id) == "drop" then mindo.remove(id) end
            end
            """, map: map)
        XCTAssertEqual(r.children.map(\.text), ["keep"])
    }

    // MARK: - Knowledge base

    func testKBResolveAndBacklinks() throws {
        let files = [URL(fileURLWithPath: "/ws/Architecture.md"),
                     URL(fileURLWithPath: "/ws/Auth.md"),
                     URL(fileURLWithPath: "/ws/Billing.md")]
        let corpus: [(url: URL, text: String)] = [
            (files[1], "see [[Architecture]] for details"),
            (files[2], "also [[Architecture]] applies"),
        ]
        let map = MindMap(root: Topic(text: "Root"))
        let r = try run("""
            return mindo.resolve("Architecture")
            """, map: map, corpus: corpus, allFiles: files)
        XCTAssertEqual(r.stringValue, "Architecture")

        let back = try run("""
            local names = mindo.backlinks("Architecture")
            return table.concat(names, ",")
            """, map: map, corpus: corpus, allFiles: files)
        XCTAssertEqual(back.stringValue, "Auth,Billing")
    }

    func testResolveMissingReturnsNil() throws {
        let map = MindMap(root: Topic(text: "Root"))
        let r = try run("return mindo.resolve('Nope') == nil", map: map, allFiles: [])
        XCTAssertEqual(r.boolValue, true)
    }

    func testInvalidHandleThrows() {
        let map = MindMap(root: Topic(text: "Root"))
        XCTAssertThrowsError(try run("return mindo.text(999)", map: map))
    }
}
