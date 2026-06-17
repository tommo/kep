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

        try engine.run(Self.prelude)
    }

    /// Lua prelude wiring the registered globals into the `mindo` namespace.
    static let prelude = """
    mindo = {
      root = __mindo_root,
      text = __mindo_text,
      setText = __mindo_setText,
      children = __mindo_children,
      addChild = __mindo_addChild,
      setAttr = __mindo_setAttr,
      attr = __mindo_attr,
      depth = __mindo_depth,
      count = __mindo_count,
      remove = __mindo_remove,
      resolve = __mindo_resolve,
      backlinks = __mindo_backlinks,
      docs = __mindo_docs,
    }
    """
}
