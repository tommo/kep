import Foundation

/// Standard topic attribute keys used by the Mindolph mind-map renderer.
public enum TopicAttribute {
    public static let fillColor = "fillColor"
    public static let textColor = "textColor"
    public static let borderColor = "borderColor"
    public static let leftSide = "leftSide"
    public static let collapsed = "collapsed"
    public static let emoticon = "mmd.emoticon"
    public static let image = "mmd.image"
    /// Edge connector color preserved from FreeMind imports (#RRGGBB).
    public static let edgeColor = "edgeColor"
    /// Edge style preserved from FreeMind imports (e.g. `bezier`, `linear`).
    public static let edgeStyle = "edgeStyle"
    /// Edge width preserved from FreeMind imports (e.g. `thin`, `1`, `2`).
    public static let edgeWidth = "edgeWidth"
    /// Per-topic text alignment override (`left` | `center` | `right`).
    /// Absent attribute falls back to the default centered layout.
    public static let textAlign = "textAlign"
    /// Manual layout nudge (points) applied on top of the auto-layout position;
    /// the node and its subtree shift by (offsetX, offsetY). Absent = 0.
    public static let offsetX = "offsetX"
    public static let offsetY = "offsetY"
}

/// A node in a mind map's topic tree. Mirrors `Topic<T>` from `mindmap-model`.
public final class Topic {
    public weak var map: MindMap?
    public weak var parent: Topic?
    public private(set) var children: [Topic] = []

    public var text: String

    /// Topic-level attributes, sorted serialization order. Use a sorted dict via `attributesAsString`.
    public private(set) var attributes: [String: String] = [:]

    /// Extras keyed by type — at most one per type, mirroring Java's `EnumMap`.
    public private(set) var extras: [ExtraType: any Extra] = [:]

    /// Map from language → snippet body. `keys` are sorted on serialization.
    public private(set) var codeSnippets: [String: String] = [:]

    /// Transient rendering payload (not serialized) — used by the mindmap canvas.
    public var payload: Any?

    public init(text: String, parent: Topic? = nil, map: MindMap? = nil) {
        self.text = text
        self.parent = parent
        self.map = map
    }

    // MARK: - Tree mutation

    @discardableResult
    public func addChild(text: String) -> Topic {
        let child = Topic(text: text, parent: self, map: map)
        children.append(child)
        return child
    }

    public func append(_ child: Topic) {
        child.parent = self
        child.map = map
        children.append(child)
    }

    public func removeChild(_ child: Topic) {
        children.removeAll { $0 === child }
    }

    /// Insert an existing child at a specific index (clamped to a valid range),
    /// adopting it. Use to position a freshly-added or reparented topic.
    public func insert(_ child: Topic, at index: Int) {
        child.parent = self
        child.map = map
        let i = max(0, min(index, children.count))
        children.insert(child, at: i)
    }

    /// Replace the child order with `ordered` (must be a permutation of the
    /// current children — same elements, any order). No-op otherwise. Used by
    /// sort + its undo.
    public func reorderChildren(_ ordered: [Topic]) {
        guard ordered.count == children.count,
              Set(ordered.map(ObjectIdentifier.init)) == Set(children.map(ObjectIdentifier.init)) else { return }
        children = ordered
    }

    /// Sort immediate children by text (localized, case-insensitive). Set
    /// `recursive` to sort the whole subtree. Pure model mutation.
    public func sortChildren(recursive: Bool = false, ascending: Bool = true) {
        children.sort { a, b in
            let r = a.text.localizedCaseInsensitiveCompare(b.text)
            return ascending ? r == .orderedAscending : r == .orderedDescending
        }
        if recursive { children.forEach { $0.sortChildren(recursive: true, ascending: ascending) } }
    }

    /// Move `child` (which must already be in `children`) to the given index,
    /// clamped to `[0, count-1]`. No-op if `child` isn't a child or already there.
    public func move(child: Topic, to index: Int) {
        guard let from = children.firstIndex(where: { $0 === child }) else { return }
        let to = max(0, min(index, children.count - 1))
        if from == to { return }
        let moving = children.remove(at: from)
        children.insert(moving, at: to)
    }

    /// Mirror of Java `Topic.findParentForDepth(int)`: starts from `self.parent`
    /// (one step up) then walks `n` *additional* steps, so n=0 returns the
    /// parent and n=1 returns the grandparent. Used by the `.mmd` parser to
    /// resolve "this heading belongs N levels above where I am now".
    public func findParent(forDepth n: Int) -> Topic? {
        var result = self.parent
        var remaining = n
        while remaining > 0, let next = result?.parent {
            result = next
            remaining -= 1
        }
        return result
    }

    public var isRoot: Bool { parent == nil }

    public var root: Topic {
        var t = self
        while let p = t.parent { t = p }
        return t
    }

    public var depth: Int {
        var d = 0
        var t = self
        while let p = t.parent { d += 1; t = p }
        return d
    }

    /// Stable outline path: "" for root, "0/2" for the 3rd child of the 1st
    /// child of root. Walks up to the root collecting child indices.
    public var outlinePath: String {
        var comps: [String] = []
        var node = self
        while let parent = node.parent {
            guard let idx = parent.children.firstIndex(where: { $0 === node }) else { break }
            comps.append(String(idx))
            node = parent
        }
        return comps.reversed().joined(separator: "/")
    }

    /// True if `self` is `ancestor` itself or anywhere in its subtree (i.e.
    /// `ancestor` is on the path from `self` up to the root).
    public func isDescendant(of ancestor: Topic) -> Bool {
        var node: Topic? = self
        while let n = node { if n === ancestor { return true }; node = n.parent }
        return false
    }

    // MARK: - Attributes / extras / snippets

    public func setAttribute(_ key: String, _ value: String?) {
        if let v = value { attributes[key] = v } else { attributes.removeValue(forKey: key) }
    }

    public func attribute(_ key: String) -> String? { attributes[key] }

    public func putAttributes(_ kv: [String: String]) {
        for (k, v) in kv { attributes[k] = v }
    }

    public func setExtra(_ extra: any Extra) {
        extras[extra.type] = extra
    }

    public func removeExtra(_ type: ExtraType) {
        extras.removeValue(forKey: type)
    }

    public func extra(_ type: ExtraType) -> (any Extra)? { extras[type] }

    public func putCodeSnippet(language: String, body: String) {
        codeSnippets[language] = body
    }

    // MARK: - Serialization

    /// Recursive write — emits this topic and its subtree.
    /// Format: `\n` + `#…` + ` ` + escaped text + `\n` + (attrs) + (extras) + (snippets) + children…
    public func write(to out: inout String, level: Int) {
        out.append(MmdConstants.nextLine)
        out.append(String(repeating: "#", count: level))
        out.append(" ")
        out.append(ModelUtils.escapeMarkdown(text))
        out.append(MmdConstants.nextLine)

        if !attributes.isEmpty || !extras.isEmpty {
            var combined = attributes
            for extra in extras.values {
                extra.addAttributesForWrite(&combined)
            }
            if !combined.isEmpty {
                out.append("> ")
                out.append(MindMap.attributesAsString(combined))
                out.append(MmdConstants.nextLine)
                out.append(MmdConstants.nextLine)
            }
        }

        if !extras.isEmpty {
            // Sort by enum case name to match Java's Comparator.comparing(Enum::name).
            let sortedTypes = extras.keys.sorted { $0.rawName < $1.rawName }
            for type in sortedTypes {
                if let extra = extras[type] {
                    extra.write(to: &out)
                    out.append(MmdConstants.nextLine)
                }
            }
        }

        if !codeSnippets.isEmpty {
            let langs = codeSnippets.keys.sorted()
            for lang in langs {
                guard let body = codeSnippets[lang] else { continue }
                let fenceCount = max(3, ModelUtils.calcMaxBacktickRun(in: body) + 1)
                let fence = String(repeating: "`", count: fenceCount)
                out.append(fence)
                out.append(lang)
                out.append(MmdConstants.nextLine)
                out.append(body)
                if !body.hasSuffix("\n") { out.append(MmdConstants.nextLine) }
                out.append(fence)
                out.append(MmdConstants.nextLine)
            }
        }

        for child in children {
            child.write(to: &out, level: level + 1)
        }
    }

    /// Build an independent copy of this topic. Shares Extra references
    /// since all built-in Extras are immutable, but `attributes`,
    /// `codeSnippets`, and `children` are deep-copied so mutations on the
    /// clone (or source) don't bleed across. `parent` and `map` are left
    /// nil on the new node — caller is expected to attach it via
    /// `parent.append(_:)`. When `deep` is false only this node is cloned;
    /// children are dropped.
    public func clone(deep: Bool) -> Topic {
        let copy = Topic(text: text)
        copy.attributes = attributes
        copy.extras = extras
        copy.codeSnippets = codeSnippets
        if deep {
            for child in children {
                let childCopy = child.clone(deep: true)
                copy.append(childCopy)
            }
        }
        return copy
    }

    /// Total number of topics in this subtree (including self).
    public func subtreeCount() -> Int {
        var n = 1
        for c in children { n += c.subtreeCount() }
        return n
    }

    /// Pre-order traversal of this subtree.
    public func traverse(_ visit: (Topic) -> Void) {
        visit(self)
        for c in children { c.traverse(visit) }
    }
}
