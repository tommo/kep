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

    func testAllTraversesWholeTreePreOrder() throws {
        let map = MindMap(root: Topic(text: "R"))
        _ = try run("""
            local r = mindo.root()
            local a = mindo.addChild(r, "A")
            mindo.addChild(a, "A1")
            mindo.addChild(r, "B")
            """, map: map)
        // Now count every node via mindo.all() in a fresh run over the same map.
        let n = try run("return #mindo.all()", map: map)
        XCTAssertEqual(n.numberValue, 4)   // R, A, A1, B
    }

    func testBatchEditAcrossWholeTree() throws {
        let map = MindMap(root: Topic(text: "TODO root"))
        let r = map.root!
        let a = r.addChild(text: "branch")
        _ = a.addChild(text: "TODO deep")        // a grandchild, not a direct child of root
        _ = try run("""
            for _, id in ipairs(mindo.all()) do
              if string.find(mindo.text(id), "TODO") then
                mindo.setAttr(id, "flag", "1")
              end
            end
            """, map: map)
        var flagged: [String] = []
        r.traverse { if $0.attribute("flag") == "1" { flagged.append($0.text) } }
        XCTAssertEqual(Set(flagged), ["TODO root", "TODO deep"])
    }

    func testParentAndIsRoot() throws {
        let map = MindMap(root: Topic(text: "R"))
        let out = try run("""
            local r = mindo.root()
            local a = mindo.addChild(r, "A")
            return tostring(mindo.isRoot(r)) .. "," .. tostring(mindo.isRoot(a)) .. "," .. (mindo.parent(a) == r and "yes" or "no")
            """, map: map)
        XCTAssertEqual(out.stringValue, "true,false,yes")
    }

    func testParentOfRootIsNil() throws {
        let map = MindMap(root: Topic(text: "R"))
        let out = try run("return mindo.parent(mindo.root()) == nil", map: map)
        XCTAssertEqual(out.boolValue, true)
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

    // MARK: - Extended API (find / move / link / note / collapse / path / readDoc)

    func testFindReturnsMatchingTopics() throws {
        let map = MindMap(root: Topic(text: "Espresso"))
        let r = map.root!
        let eq = r.addChild(text: "Equipment")
        _ = eq.addChild(text: "Espresso Machine")
        _ = r.addChild(text: "Beans")
        let out = try run("""
            local hits = mindo.find("espresso")
            local t = {}
            for _, id in ipairs(hits) do t[#t+1] = mindo.text(id) end
            return table.concat(t, "|")
            """, map: map)
        XCTAssertEqual(Set(out.stringValue!.split(separator: "|").map(String.init)),
                       ["Espresso", "Espresso Machine"])
    }

    func testMoveReparents() throws {
        let map = MindMap(root: Topic(text: "R"))
        _ = try run("""
            local r = mindo.root()
            local a = mindo.addChild(r, "A")
            local b = mindo.addChild(r, "B")
            local x = mindo.addChild(a, "X")
            mindo.move(x, b)          -- move X from A to B
            """, map: map)
        let r = map.root!
        XCTAssertEqual(r.children[0].children.map(\.text), [])          // A now empty
        XCTAssertEqual(r.children[1].children.map(\.text), ["X"])       // B has X
    }

    func testMoveRejectsCycle() {
        let map = MindMap(root: Topic(text: "R"))
        XCTAssertThrowsError(try run("""
            local r = mindo.root()
            local a = mindo.addChild(r, "A")
            local b = mindo.addChild(a, "B")
            mindo.move(a, b)          -- a under its own descendant → error
            """, map: map))
    }

    func testMoveWithIndex() throws {
        let map = MindMap(root: Topic(text: "R"))
        _ = try run("""
            local r = mindo.root()
            local a = mindo.addChild(r, "A")
            local b = mindo.addChild(r, "B")
            local c = mindo.addChild(r, "C")
            mindo.move(c, r, 0)       -- move C to front of root's children
            """, map: map)
        XCTAssertEqual(map.root!.children.map(\.text), ["C", "A", "B"])
    }

    func testNoteRoundTrip() throws {
        let map = MindMap(root: Topic(text: "R"))
        let out = try run("""
            local r = mindo.root()
            mindo.setNote(r, "remember this")
            return mindo.note(r)
            """, map: map)
        XCTAssertEqual(out.stringValue, "remember this")
        XCTAssertEqual((map.root?.extra(.note) as? ExtraNote)?.text, "remember this")
    }

    func testLinkCreatesJumpLink() throws {
        let map = MindMap(root: Topic(text: "R"))
        _ = try run("""
            local r = mindo.root()
            local a = mindo.addChild(r, "A")
            local b = mindo.addChild(r, "B")
            mindo.link(a, b)
            """, map: map)
        let r = map.root!
        let a = r.children[0], b = r.children[1]
        let uid = b.attribute(ExtraTopic.topicUidAttr)
        XCTAssertNotNil(uid)
        XCTAssertEqual((a.extra(.topic) as? ExtraTopic)?.topicUID, uid)
    }

    func testSetCollapsedAndPath() throws {
        let map = MindMap(root: Topic(text: "R"))
        let out = try run("""
            local r = mindo.root()
            local a = mindo.addChild(r, "A")
            local x = mindo.addChild(a, "X")
            mindo.setCollapsed(a, true)
            return mindo.path(x)
            """, map: map)
        XCTAssertEqual(out.stringValue, "0/0")
        XCTAssertEqual(map.root?.children[0].attribute("collapsed"), "true")
    }

    func testSortChildren() throws {
        let map = MindMap(root: Topic(text: "R"))
        let r = map.root!
        _ = r.addChild(text: "banana"); _ = r.addChild(text: "Apple"); _ = r.addChild(text: "cherry")
        _ = try run("mindo.sort(mindo.root())", map: map)
        XCTAssertEqual(r.children.map(\.text), ["Apple", "banana", "cherry"])
        _ = try run("mindo.sort(mindo.root(), false)", map: map)   // descending
        XCTAssertEqual(r.children.map(\.text), ["cherry", "banana", "Apple"])
    }

    func testReadDoc() throws {
        let files = [URL(fileURLWithPath: "/ws/Notes.md")]
        let corpus: [(url: URL, text: String)] = [(files[0], "# Notes\nbody here")]
        let map = MindMap(root: Topic(text: "R"))
        let out = try run("return mindo.readDoc('Notes')", map: map, corpus: corpus, allFiles: files)
        XCTAssertEqual(out.stringValue, "# Notes\nbody here")
        let miss = try run("return mindo.readDoc('Nope') == nil", map: map, corpus: corpus, allFiles: files)
        XCTAssertEqual(miss.boolValue, true)
    }
}
