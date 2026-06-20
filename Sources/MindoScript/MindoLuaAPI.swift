import Foundation
import LuaSwift
import MindoModel
import MindoCore

struct MindoScriptError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

/// Binds a `mindo` API into a Lua engine so scripts can build, traverse, and
/// edit a mind map and query the knowledge base. Topics are passed to Lua as
/// opaque integer ids (mapped back to `Topic` here); mutations apply directly to
/// the `MindMap` (the app wraps a run in one undo group).
public final class MindoLuaAPI {
    public let map: MindMap
    private var idToTopic: [Int: Topic] = [:]
    private var topicToId: [ObjectIdentifier: Int] = [:]
    private var nextId = 1

    /// KB corpus: (file URL, text) to scan, and the resolution namespace.
    private let corpus: [(url: URL, text: String)]
    private let allFiles: [URL]

    public init(map: MindMap,
                corpus: [(url: URL, text: String)] = [],
                allFiles: [URL] = []) {
        self.map = map
        self.corpus = corpus
        self.allFiles = allFiles
        if map.root == nil { map.root = Topic(text: "Root") }
    }

    // MARK: - id ↔ Topic

    private func id(for topic: Topic) -> Int {
        let oid = ObjectIdentifier(topic)
        if let i = topicToId[oid] { return i }
        let i = nextId; nextId += 1
        idToTopic[i] = topic; topicToId[oid] = i
        return i
    }

    private func topic(_ args: [LuaValue], _ i: Int = 0) throws -> Topic {
        guard let raw = (i < args.count ? args[i] : .nil).intValue, let t = idToTopic[raw] else {
            throw MindoScriptError(message: "mindo: invalid topic handle")
        }
        return t
    }

    private func string(_ args: [LuaValue], _ i: Int) throws -> String {
        guard let s = (i < args.count ? args[i] : .nil).stringValue else {
            throw MindoScriptError(message: "mindo: expected a string argument")
        }
        return s
    }

    private func baseName(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    // MARK: - Install

    /// Register the host functions and define the `mindo` table in the engine.
    public func install(on engine: LuaScriptEngine) throws {
        engine.register("__mindo_root") { [self] _ in .number(Double(id(for: map.root!))) }
        engine.register("__mindo_all") { [self] _ in
            guard let root = map.root else { return .array([]) }
            var ids: [LuaValue] = []
            root.traverse { ids.append(.number(Double(id(for: $0)))) }   // pre-order
            return .array(ids)
        }
        engine.register("__mindo_parent") { [self] a in
            (try topic(a).parent).map { .number(Double(id(for: $0))) } ?? .nil
        }
        engine.register("__mindo_isRoot") { [self] a in .bool(try topic(a).isRoot) }
        engine.register("__mindo_text") { [self] a in .string(try topic(a).text) }
        engine.register("__mindo_setText") { [self] a in try topic(a).text = try string(a, 1); return .nil }
        engine.register("__mindo_children") { [self] a in
            .array(try topic(a).children.map { .number(Double(id(for: $0))) })
        }
        engine.register("__mindo_addChild") { [self] a in
            let child = try topic(a).addChild(text: try string(a, 1))
            return .number(Double(id(for: child)))
        }
        engine.register("__mindo_setAttr") { [self] a in
            let t = try topic(a)
            let key = try string(a, 1)
            let value = a.count > 2 ? a[2].stringValue : nil   // nil → remove
            t.setAttribute(key, value)
            return .nil
        }
        engine.register("__mindo_attr") { [self] a in
            (try topic(a).attribute(try string(a, 1))).map { LuaValue.string($0) } ?? .nil
        }
        engine.register("__mindo_depth") { [self] a in .number(Double(try topic(a).depth)) }
        engine.register("__mindo_count") { [self] a in .number(Double(try topic(a).children.count)) }
        engine.register("__mindo_remove") { [self] a in
            let t = try topic(a)
            t.parent?.removeChild(t)
            return .nil
        }
        // Structure: find, move/reparent, jump-links, notes, collapse, path
        engine.register("__mindo_find") { [self] a in
            let needle = (try string(a, 0)).lowercased()
            guard let root = map.root else { return .array([]) }
            var hits: [LuaValue] = []
            root.traverse { if $0.text.lowercased().contains(needle) { hits.append(.number(Double(id(for: $0)))) } }
            return .array(hits)
        }
        engine.register("__mindo_move") { [self] a in
            let t = try topic(a)
            let newParent = try topic(a, 1)
            guard t.parent != nil else { throw MindoScriptError(message: "mindo.move: can't move the root") }
            if newParent === t || newParent.isDescendant(of: t) {
                throw MindoScriptError(message: "mindo.move: can't move a topic under itself or its descendant")
            }
            t.parent?.removeChild(t)
            if a.count > 2, let idx = a[2].intValue { newParent.insert(t, at: idx) } else { newParent.append(t) }
            return .nil
        }
        engine.register("__mindo_link") { [self] a in
            let source = try topic(a)
            let target = try topic(a, 1)
            guard source !== target else { throw MindoScriptError(message: "mindo.link: source and target are the same") }
            var uid = target.attribute(ExtraTopic.topicUidAttr)
            if uid == nil { let g = UUID().uuidString; target.setAttribute(ExtraTopic.topicUidAttr, g); uid = g }
            source.setExtra(ExtraTopic(topicUID: uid!))
            return .nil
        }
        engine.register("__mindo_note") { [self] a in
            (try topic(a).extra(.note) as? ExtraNote).map { LuaValue.string($0.text) } ?? .nil
        }
        engine.register("__mindo_setNote") { [self] a in
            try topic(a).setExtra(ExtraNote(text: try string(a, 1))); return .nil
        }
        engine.register("__mindo_setCollapsed") { [self] a in
            let t = try topic(a)
            let on = a.count > 1 ? (a[1].boolValue ?? false) : true
            t.setAttribute("collapsed", on ? "true" : nil)
            return .nil
        }
        engine.register("__mindo_path") { [self] a in .string(try topic(a).outlinePath) }
        engine.register("__mindo_sort") { [self] a in
            let t = try topic(a)
            let ascending = a.count > 1 ? (a[1].boolValue ?? true) : true
            t.sortChildren(ascending: ascending)
            return .nil
        }
        // Knowledge base
        engine.register("__mindo_resolve") { [self] a in
            let target = try string(a, 0)
            guard let url = WikiLinkResolver.resolve(target, in: allFiles) else { return .nil }
            return .string(baseName(url))
        }
        engine.register("__mindo_backlinks") { [self] a in
            let name = try string(a, 0)
            guard let target = WikiLinkResolver.resolve(name, in: allFiles) else { return .array([]) }
            let sources = Backlinks.sources(to: target, corpus: corpus, allFiles: allFiles)
            return .array(sources.map { .string(baseName($0)) })
        }
        engine.register("__mindo_docs") { [self] _ in
            .array(allFiles.map { .string(baseName($0)) })
        }
        engine.register("__mindo_readDoc") { [self] a in
            let name = try string(a, 0)
            guard let url = WikiLinkResolver.resolve(name, in: allFiles) else { return .nil }
            if let entry = corpus.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                return .string(entry.text)
            }
            return (try? String(contentsOf: url, encoding: .utf8)).map { LuaValue.string($0) } ?? .nil
        }

        try engine.run(Self.prelude)
    }

    /// Lua prelude wiring the registered globals into the `mindo` namespace.
    static let prelude = """
    mindo = {
      root = __mindo_root,
      all = __mindo_all,
      parent = __mindo_parent,
      isRoot = __mindo_isRoot,
      text = __mindo_text,
      setText = __mindo_setText,
      children = __mindo_children,
      addChild = __mindo_addChild,
      setAttr = __mindo_setAttr,
      attr = __mindo_attr,
      depth = __mindo_depth,
      count = __mindo_count,
      remove = __mindo_remove,
      find = __mindo_find,
      move = __mindo_move,
      link = __mindo_link,
      note = __mindo_note,
      setNote = __mindo_setNote,
      setCollapsed = __mindo_setCollapsed,
      path = __mindo_path,
      sort = __mindo_sort,
      resolve = __mindo_resolve,
      backlinks = __mindo_backlinks,
      docs = __mindo_docs,
      readDoc = __mindo_readDoc,
    }
    """
}
