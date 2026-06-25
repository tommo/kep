import Foundation
import LuaSwift
import KepModel
import KepCore

struct KepScriptError: Error, CustomStringConvertible, LocalizedError {
    let message: String
    var description: String { message }
    // So a host-callback failure surfaces `message` (not the opaque localized
    // NSError) when LuaSwift wraps it as "Swift callback error: …".
    var errorDescription: String? { message }
}

/// Binds a `kep` API into a Lua engine so scripts can build, traverse, and
/// edit a mind map and query the knowledge base. Topics are passed to Lua as
/// opaque integer ids (mapped back to `Topic` here); mutations apply directly to
/// the `MindMap` (the app wraps a run in one undo group).
public final class KepLuaAPI {
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
            throw KepScriptError(message: "kep: invalid topic handle")
        }
        return t
    }

    private func string(_ args: [LuaValue], _ i: Int) throws -> String {
        guard let s = (i < args.count ? args[i] : .nil).stringValue else {
            throw KepScriptError(message: "kep: expected a string argument")
        }
        return s
    }

    private func baseName(_ url: URL) -> String { url.deletingPathExtension().lastPathComponent }

    // MARK: - Install

    /// Register the host functions and define the `kep` table in the engine.
    public func install(on engine: LuaScriptEngine) throws {
        engine.register("__kep_root") { [self] _ in .number(Double(id(for: map.root!))) }
        engine.register("__kep_all") { [self] _ in
            guard let root = map.root else { return .array([]) }
            var ids: [LuaValue] = []
            root.traverse { ids.append(.number(Double(id(for: $0)))) }   // pre-order
            return .array(ids)
        }
        engine.register("__kep_parent") { [self] a in
            (try topic(a).parent).map { .number(Double(id(for: $0))) } ?? .nil
        }
        engine.register("__kep_isRoot") { [self] a in .bool(try topic(a).isRoot) }
        engine.register("__kep_text") { [self] a in .string(try topic(a).text) }
        engine.register("__kep_setText") { [self] a in try topic(a).text = try string(a, 1); return .nil }
        engine.register("__kep_children") { [self] a in
            .array(try topic(a).children.map { .number(Double(id(for: $0))) })
        }
        engine.register("__kep_addChild") { [self] a in
            let child = try topic(a).addChild(text: try string(a, 1))
            return .number(Double(id(for: child)))
        }
        engine.register("__kep_setAttr") { [self] a in
            let t = try topic(a)
            let key = try string(a, 1)
            let value = a.count > 2 ? a[2].stringValue : nil   // nil → remove
            t.setAttribute(key, value)
            return .nil
        }
        engine.register("__kep_attr") { [self] a in
            (try topic(a).attribute(try string(a, 1))).map { LuaValue.string($0) } ?? .nil
        }
        engine.register("__kep_depth") { [self] a in .number(Double(try topic(a).depth)) }
        engine.register("__kep_count") { [self] a in .number(Double(try topic(a).children.count)) }
        engine.register("__kep_remove") { [self] a in
            let t = try topic(a)
            t.parent?.removeChild(t)
            return .nil
        }
        // Structure: find, move/reparent, jump-links, notes, collapse, path
        engine.register("__kep_find") { [self] a in
            let needle = (try string(a, 0)).lowercased()
            guard let root = map.root else { return .array([]) }
            var hits: [LuaValue] = []
            root.traverse { if $0.text.lowercased().contains(needle) { hits.append(.number(Double(id(for: $0)))) } }
            return .array(hits)
        }
        engine.register("__kep_move") { [self] a in
            let t = try topic(a)
            let newParent = try topic(a, 1)
            guard t.parent != nil else { throw KepScriptError(message: "kep.move: can't move the root") }
            if newParent === t || newParent.isDescendant(of: t) {
                throw KepScriptError(message: "kep.move: can't move a topic under itself or its descendant")
            }
            t.parent?.removeChild(t)
            if a.count > 2, let idx = a[2].intValue { newParent.insert(t, at: idx) } else { newParent.append(t) }
            return .nil
        }
        engine.register("__kep_link") { [self] a in
            let source = try topic(a)
            let target = try topic(a, 1)
            guard source !== target else { throw KepScriptError(message: "kep.link: source and target are the same") }
            var uid = target.attribute(ExtraTopic.topicUidAttr)
            if uid == nil { let g = UUID().uuidString; target.setAttribute(ExtraTopic.topicUidAttr, g); uid = g }
            source.setExtra(ExtraTopic(topicUID: uid!))
            return .nil
        }
        engine.register("__kep_note") { [self] a in
            (try topic(a).extra(.note) as? ExtraNote).map { LuaValue.string($0.text) } ?? .nil
        }
        engine.register("__kep_setNote") { [self] a in
            try topic(a).setExtra(ExtraNote(text: try string(a, 1))); return .nil
        }
        engine.register("__kep_setCollapsed") { [self] a in
            let t = try topic(a)
            let on = a.count > 1 ? (a[1].boolValue ?? false) : true
            t.setAttribute("collapsed", on ? "true" : nil)
            return .nil
        }
        engine.register("__kep_path") { [self] a in .string(try topic(a).outlinePath) }
        engine.register("__kep_sort") { [self] a in
            let t = try topic(a)
            let ascending = a.count > 1 ? (a[1].boolValue ?? true) : true
            t.sortChildren(ascending: ascending)
            return .nil
        }
        // Knowledge base
        engine.register("__kep_resolve") { [self] a in
            let target = try string(a, 0)
            guard let url = WikiLinkResolver.resolve(target, in: allFiles) else { return .nil }
            return .string(baseName(url))
        }
        engine.register("__kep_backlinks") { [self] a in
            let name = try string(a, 0)
            guard let target = WikiLinkResolver.resolve(name, in: allFiles) else { return .array([]) }
            let sources = Backlinks.sources(to: target, corpus: corpus, allFiles: allFiles)
            return .array(sources.map { .string(baseName($0)) })
        }
        engine.register("__kep_docs") { [self] _ in
            .array(allFiles.map { .string(baseName($0)) })
        }
        // Literal keyword search over the workspace corpus → up to 20 lines of
        // "Doc — …snippet…" (case-insensitive). For composable in-code research;
        // the agent also has embedding-based semantic_search for meaning.
        engine.register("__kep_search") { [self] a in
            let q = ((a.first ?? .nil).stringValue ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !q.isEmpty else { return .array([]) }
            var hits: [LuaValue] = []
            for entry in corpus {
                let text = entry.text
                guard let r = text.range(of: q, options: .caseInsensitive) else { continue }
                let lo = text.index(r.lowerBound, offsetBy: -50, limitedBy: text.startIndex) ?? text.startIndex
                let hi = text.index(r.upperBound, offsetBy: 50, limitedBy: text.endIndex) ?? text.endIndex
                let snippet = text[lo..<hi].replacingOccurrences(of: "\n", with: " ")
                hits.append(.string("\(baseName(entry.url)) — …\(snippet)…"))
                if hits.count >= 20 { break }
            }
            return .array(hits)
        }
        // Embedding-based (meaning) search over the corpus → up to k lines of
        // "Doc [score]: passage". Same on-device index the agent's old JSON
        // semantic_search used; empty array when embeddings are unavailable
        // (the caller can fall back to the literal kep.search).
        engine.register("__kep_semanticSearch") { [self] a in
            let query = ((a.first ?? .nil).stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return .array([]) }
            let k = (a.count > 1 ? a[1].intValue : nil) ?? 5
            let embedder = NLTextEmbedder()
            guard embedder.isAvailable else { return .array([]) }
            let docs = corpus.map { (doc: baseName($0.url), text: $0.text) }
            var hasher = Hasher()
            for d in docs { hasher.combine(d.doc); hasher.combine(d.text) }
            let index = SemanticIndexCache.shared.index(forKey: hasher.finalize()) {
                SemanticIndex(documents: docs, embedder: embedder)
            }
            guard index.chunkCount > 0 else { return .array([]) }
            return .array(index.query(query, embedder: embedder, topK: k).map { hit in
                let snip = hit.text.replacingOccurrences(of: "\n", with: " ")
                let capped = snip.count > 240 ? String(snip.prefix(240)) + "…" : snip
                return .string("\(hit.doc) [\(String(format: "%.2f", hit.score))]: \(capped)")
            })
        }
        engine.register("__kep_readDoc") { [self] a in
            let name = try string(a, 0)
            guard let url = WikiLinkResolver.resolve(name, in: allFiles) else { return .nil }
            if let entry = corpus.first(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
                return .string(entry.text)
            }
            return (try? String(contentsOf: url, encoding: .utf8)).map { LuaValue.string($0) } ?? .nil
        }

        try engine.run(Self.prelude)
    }

    /// Lua prelude wiring the registered globals into the `kep` namespace.
    /// `kep` remains as a back-compat alias (same table) for notebooks/scripts
    /// written before the rebrand and for any `notebook.lua` that extends it.
    static let prelude = """
    kep = {
      root = __kep_root,
      all = __kep_all,
      parent = __kep_parent,
      isRoot = __kep_isRoot,
      text = __kep_text,
      setText = __kep_setText,
      children = __kep_children,
      addChild = __kep_addChild,
      setAttr = __kep_setAttr,
      attr = __kep_attr,
      depth = __kep_depth,
      count = __kep_count,
      remove = __kep_remove,
      find = __kep_find,
      move = __kep_move,
      link = __kep_link,
      note = __kep_note,
      setNote = __kep_setNote,
      setCollapsed = __kep_setCollapsed,
      path = __kep_path,
      sort = __kep_sort,
      resolve = __kep_resolve,
      backlinks = __kep_backlinks,
      docs = __kep_docs,
      readDoc = __kep_readDoc,
      search = __kep_search,
      semanticSearch = __kep_semanticSearch,
    }
    kep = kep   -- deprecated alias (pre-rebrand notebooks/scripts)
    """
}
