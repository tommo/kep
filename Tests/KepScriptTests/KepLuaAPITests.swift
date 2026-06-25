import XCTest
import LuaSwift
import KepModel
@testable import KepScript

final class KepLuaAPITests: XCTestCase {

    private func run(_ script: String, map: MindMap,
                     corpus: [(url: URL, text: String)] = [], allFiles: [URL] = []) throws -> LuaValue {
        let api = KepLuaAPI(map: map, corpus: corpus, allFiles: allFiles)
        let engine = try LuaScriptEngine()
        try api.install(on: engine)
        return try engine.run(script)
    }

    func testKepIsPrimaryAndKepIsAlias() throws {
        let map = MindMap(root: Topic(text: "Root"))
        // `kep` is the user-facing namespace after the rebrand; `kep` is the
        // same table (deprecated alias) so pre-rebrand notebooks keep working.
        let r = try run("""
            local sameTable = (kep == kep)
            local viaKep = kep.text(kep.root())
            local viaAlias = kep.text(kep.root())
            return tostring(sameTable) .. "/" .. viaKep .. "/" .. viaAlias
            """, map: map)
        XCTAssertEqual(r.stringValue, "true/Root/Root")
    }

    func testBuildTree() throws {
        let map = MindMap(root: Topic(text: "Espresso"))
        _ = try run("""
            local r = kep.root()
            local eq = kep.addChild(r, "Equipment")
            kep.addChild(eq, "Grinder")
            kep.addChild(eq, "Machine")
            kep.addChild(r, "Variables")
            """, map: map)
        let root = map.root!
        XCTAssertEqual(root.children.map(\.text), ["Equipment", "Variables"])
        XCTAssertEqual(root.children[0].children.map(\.text), ["Grinder", "Machine"])
    }

    func testReadTextDepthCount() throws {
        let map = MindMap(root: Topic(text: "Root"))
        let r = try run("""
            local r = kep.root()
            local a = kep.addChild(r, "A")
            kep.addChild(a, "B")
            -- numbers are floats in the bridge; floor for a clean integer string
            return kep.text(r) .. "/" .. math.floor(kep.count(r)) .. "/" .. math.floor(kep.depth(a))
            """, map: map)
        XCTAssertEqual(r.stringValue, "Root/1/1")
    }

    func testSetTextAndAttributes() throws {
        let map = MindMap(root: Topic(text: "Root"))
        _ = try run("""
            local r = kep.root()
            kep.setText(r, "Renamed")
            kep.setAttr(r, "fillColor", "#ffcdd2")
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
            local r = kep.root()
            for _, id in ipairs(kep.children(r)) do
              if string.find(kep.text(id), "TODO") then
                kep.setAttr(id, "fillColor", "#ffcdd2")
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
            local r = kep.root()
            for _, id in ipairs(kep.children(r)) do
              if kep.text(id) == "drop" then kep.remove(id) end
            end
            """, map: map)
        XCTAssertEqual(r.children.map(\.text), ["keep"])
    }

    func testAllTraversesWholeTreePreOrder() throws {
        let map = MindMap(root: Topic(text: "R"))
        _ = try run("""
            local r = kep.root()
            local a = kep.addChild(r, "A")
            kep.addChild(a, "A1")
            kep.addChild(r, "B")
            """, map: map)
        // Now count every node via kep.all() in a fresh run over the same map.
        let n = try run("return #kep.all()", map: map)
        XCTAssertEqual(n.numberValue, 4)   // R, A, A1, B
    }

    func testBatchEditAcrossWholeTree() throws {
        let map = MindMap(root: Topic(text: "TODO root"))
        let r = map.root!
        let a = r.addChild(text: "branch")
        _ = a.addChild(text: "TODO deep")        // a grandchild, not a direct child of root
        _ = try run("""
            for _, id in ipairs(kep.all()) do
              if string.find(kep.text(id), "TODO") then
                kep.setAttr(id, "flag", "1")
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
            local r = kep.root()
            local a = kep.addChild(r, "A")
            return tostring(kep.isRoot(r)) .. "," .. tostring(kep.isRoot(a)) .. "," .. (kep.parent(a) == r and "yes" or "no")
            """, map: map)
        XCTAssertEqual(out.stringValue, "true,false,yes")
    }

    func testParentOfRootIsNil() throws {
        let map = MindMap(root: Topic(text: "R"))
        let out = try run("return kep.parent(kep.root()) == nil", map: map)
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
            return kep.resolve("Architecture")
            """, map: map, corpus: corpus, allFiles: files)
        XCTAssertEqual(r.stringValue, "Architecture")

        let back = try run("""
            local names = kep.backlinks("Architecture")
            return table.concat(names, ",")
            """, map: map, corpus: corpus, allFiles: files)
        XCTAssertEqual(back.stringValue, "Auth,Billing")
    }

    func testResolveMissingReturnsNil() throws {
        let map = MindMap(root: Topic(text: "Root"))
        let r = try run("return kep.resolve('Nope') == nil", map: map, allFiles: [])
        XCTAssertEqual(r.boolValue, true)
    }

    func testInvalidHandleThrows() {
        let map = MindMap(root: Topic(text: "Root"))
        XCTAssertThrowsError(try run("return kep.text(999)", map: map))
    }

    // MARK: - Extended API (find / move / link / note / collapse / path / readDoc)

    func testFindReturnsMatchingTopics() throws {
        let map = MindMap(root: Topic(text: "Espresso"))
        let r = map.root!
        let eq = r.addChild(text: "Equipment")
        _ = eq.addChild(text: "Espresso Machine")
        _ = r.addChild(text: "Beans")
        let out = try run("""
            local hits = kep.find("espresso")
            local t = {}
            for _, id in ipairs(hits) do t[#t+1] = kep.text(id) end
            return table.concat(t, "|")
            """, map: map)
        XCTAssertEqual(Set(out.stringValue!.split(separator: "|").map(String.init)),
                       ["Espresso", "Espresso Machine"])
    }

    func testMoveReparents() throws {
        let map = MindMap(root: Topic(text: "R"))
        _ = try run("""
            local r = kep.root()
            local a = kep.addChild(r, "A")
            local b = kep.addChild(r, "B")
            local x = kep.addChild(a, "X")
            kep.move(x, b)          -- move X from A to B
            """, map: map)
        let r = map.root!
        XCTAssertEqual(r.children[0].children.map(\.text), [])          // A now empty
        XCTAssertEqual(r.children[1].children.map(\.text), ["X"])       // B has X
    }

    func testMoveRejectsCycle() {
        let map = MindMap(root: Topic(text: "R"))
        XCTAssertThrowsError(try run("""
            local r = kep.root()
            local a = kep.addChild(r, "A")
            local b = kep.addChild(a, "B")
            kep.move(a, b)          -- a under its own descendant → error
            """, map: map))
    }

    func testMoveWithIndex() throws {
        let map = MindMap(root: Topic(text: "R"))
        _ = try run("""
            local r = kep.root()
            local a = kep.addChild(r, "A")
            local b = kep.addChild(r, "B")
            local c = kep.addChild(r, "C")
            kep.move(c, r, 0)       -- move C to front of root's children
            """, map: map)
        XCTAssertEqual(map.root!.children.map(\.text), ["C", "A", "B"])
    }

    func testNoteRoundTrip() throws {
        let map = MindMap(root: Topic(text: "R"))
        let out = try run("""
            local r = kep.root()
            kep.setNote(r, "remember this")
            return kep.note(r)
            """, map: map)
        XCTAssertEqual(out.stringValue, "remember this")
        XCTAssertEqual((map.root?.extra(.note) as? ExtraNote)?.text, "remember this")
    }

    func testLinkCreatesJumpLink() throws {
        let map = MindMap(root: Topic(text: "R"))
        _ = try run("""
            local r = kep.root()
            local a = kep.addChild(r, "A")
            local b = kep.addChild(r, "B")
            kep.link(a, b)
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
            local r = kep.root()
            local a = kep.addChild(r, "A")
            local x = kep.addChild(a, "X")
            kep.setCollapsed(a, true)
            return kep.path(x)
            """, map: map)
        XCTAssertEqual(out.stringValue, "0/0")
        XCTAssertEqual(map.root?.children[0].attribute("collapsed"), "true")
    }

    func testSortChildren() throws {
        let map = MindMap(root: Topic(text: "R"))
        let r = map.root!
        _ = r.addChild(text: "banana"); _ = r.addChild(text: "Apple"); _ = r.addChild(text: "cherry")
        _ = try run("kep.sort(kep.root())", map: map)
        XCTAssertEqual(r.children.map(\.text), ["Apple", "banana", "cherry"])
        _ = try run("kep.sort(kep.root(), false)", map: map)   // descending
        XCTAssertEqual(r.children.map(\.text), ["cherry", "banana", "Apple"])
    }

    func testReadDoc() throws {
        let files = [URL(fileURLWithPath: "/ws/Notes.md")]
        let corpus: [(url: URL, text: String)] = [(files[0], "# Notes\nbody here")]
        let map = MindMap(root: Topic(text: "R"))
        let out = try run("return kep.readDoc('Notes')", map: map, corpus: corpus, allFiles: files)
        XCTAssertEqual(out.stringValue, "# Notes\nbody here")
        let miss = try run("return kep.readDoc('Nope') == nil", map: map, corpus: corpus, allFiles: files)
        XCTAssertEqual(miss.boolValue, true)
    }
}
