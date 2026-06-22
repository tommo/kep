import Foundation

/// Top-level container for a mind map document. Mirrors `MindMap<T>` from `mindmap-model`.
public final class MindMap {
    /// Map-level attributes (e.g. `__version__`, `showJumps`).
    public private(set) var attributes: [String: String] = [:]

    public var root: Topic? {
        didSet { root?.map = self }
    }

    public init() {}

    public init(root: Topic) {
        self.root = root
        root.map = self
    }

    /// Parse a `.mmd` document. Throws on malformed header.
    public init(text: String) throws {
        var lexer = MmdLexer(buffer: text, initialState: .headLine)

        var currentRoot: Topic? = nil
        var processing = true
        while processing {
            let oldOffset = lexer.offset
            lexer.advance()
            if lexer.offset == oldOffset || lexer.tokenType == nil {
                throw MmdParseError.invalidHeader
            }

            switch lexer.tokenType {
            case .headLine:
                continue
            case .attribute:
                Self.fillMapByAttributes(line: lexer.tokenText, into: &attributes)
            case .headDelimiter:
                processing = false
                currentRoot = try Topic.parse(map: nil, lexer: &lexer)
            default:
                continue
            }
        }

        self.root = currentRoot
        currentRoot?.map = self
        self.attributes[MmdConstants.generatorVersionAttr] = MmdConstants.formatVersion
    }

    /// Serialize this map to its `.mmd` representation.
    public func write() -> String {
        var out = ""
        out.append(MmdConstants.generatorHeader)
        out.append(MmdConstants.nextParagraph)

        var attrs = attributes
        attrs[MmdConstants.generatorVersionAttr] = MmdConstants.formatVersion
        out.append("> ")
        out.append(Self.attributesAsString(attrs))
        out.append(MmdConstants.nextLine)

        out.append("---")
        out.append(MmdConstants.nextLine)

        if let root = root {
            root.write(to: &out, level: 1)
        }
        return out
    }

    public func setAttribute(_ key: String, _ value: String?) {
        if let v = value { attributes[key] = v } else { attributes.removeValue(forKey: key) }
    }

    /// Resolve an outline index-path ("", "0", "0/2") back to its topic, in the
    /// same scheme `Outline.fromMindMap` produces. Used by the property panel to
    /// turn the selected outline target into the live topic.
    public func topic(atOutlinePath path: String) -> Topic? {
        guard let root = root else { return nil }
        if path.isEmpty { return root }
        var current = root
        for component in path.split(separator: "/") {
            guard let index = Int(component), index >= 0, index < current.children.count else { return nil }
            current = current.children[index]
        }
        return current
    }

    /// Find the topic with the given `topicLinkUID` attribute. Used by
    /// ExtraTopic jump rendering to resolve a UID back to a node.
    public func findTopic(uid: String) -> Topic? {
        guard let root = root else { return nil }
        var found: Topic?
        root.traverse { topic in
            if found == nil, topic.attribute(ExtraTopic.topicUidAttr) == uid { found = topic }
        }
        return found
    }

    // MARK: - Attribute serialization helpers

    /// Produce the comma-separated `key=`value`` attribute string used in `> ` lines.
    /// Keys are sorted lexicographically to match Java's TreeMap iteration order.
    public static func attributesAsString(_ attrs: [String: String]) -> String {
        var out = ""
        var first = true
        for key in attrs.keys.sorted() {
            guard let value = attrs[key] else { continue }
            if first { first = false } else { out.append(",") }
            out.append(key)
            out.append("=")
            out.append(ModelUtils.makeMDCodeBlock(value))
        }
        return out
    }

    static let attributesLinePattern: NSRegularExpression = {
        // Java: ^\s*\>\s(.+)$
        return try! NSRegularExpression(pattern: #"^\s*\>\s(.+)$"#)
    }()

    static let attributePattern: NSRegularExpression = {
        // Java: [,]?\s*([\S]+?)\s*=\s*(\`+)(.*?)\2
        return try! NSRegularExpression(pattern: #"[,]?\s*(\S+?)\s*=\s*(`+)(.*?)\2"#, options: [.dotMatchesLineSeparators])
    }()

    @discardableResult
    static func fillMapByAttributes(line: String, into map: inout [String: String]) -> Bool {
        let nsLine = line as NSString
        let lineRange = NSRange(location: 0, length: nsLine.length)
        guard let outer = attributesLinePattern.firstMatch(in: line, range: lineRange) else { return false }
        let inside = nsLine.substring(with: outer.range(at: 1))
        let nsInside = inside as NSString
        let insideRange = NSRange(location: 0, length: nsInside.length)
        var found = false
        attributePattern.enumerateMatches(in: inside, range: insideRange) { match, _, _ in
            guard let match = match else { return }
            let key = nsInside.substring(with: match.range(at: 1))
            let raw = nsInside.substring(with: match.range(at: 3))
            // Mirror makeMDCodeBlock: strip the edge-backtick pad, then unescape
            // (backslash / newline / CR). Order matters — the writer pads AFTER
            // escaping, so we un-pad before un-escaping.
            let val = ModelUtils.unescapeAttributeValue(ModelUtils.stripCodeSpanPadding(raw))
            map[key] = val
            found = true
        }
        return found
    }
}

public enum MmdParseError: Error {
    case invalidHeader
    case unexpectedToken
}
