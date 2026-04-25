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

    /// Walk up `n` levels, returning the topic that should be the new parent.
    public func findParent(forDepth n: Int) -> Topic {
        var t = self
        var i = n
        while i > 0, let p = t.parent {
            t = p
            i -= 1
        }
        return t
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
