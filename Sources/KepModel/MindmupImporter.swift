import Foundation

/// Reads Mindmup `.mup` files into a `MindMap`. The format is JSON:
///
///     { "title": "Root", "ideas": {
///         "1":  { "title": "Child 1", "ideas": { ... } },
///         "2":  { "title": "Child 2" },
///         "-1": { "title": "Left child" }
///     } }
///
/// Keys in `ideas` are *ordering weights* (parseable as Double), not
/// sequential indices. Negative keys traditionally sit on the left of
/// the root in Mindmup's renderer; we keep that convention by stamping
/// `leftSide=true` on negatively-ordered root children.
public enum MindmupImporter {

    public enum ImportError: Error {
        case invalidJSON
        case missingRoot
    }

    public static func parse(_ jsonText: String) throws -> MindMap {
        guard let data = jsonText.data(using: .utf8) else { throw ImportError.invalidJSON }
        let any: Any
        do { any = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw ImportError.invalidJSON }
        guard let dict = any as? [String: Any] else { throw ImportError.missingRoot }
        let map = MindMap()

        // Two flavors of `.mup` exist in the wild:
        //
        //   (1) "Simplified": top-level dict IS the root — `title` is
        //       the root's text, `ideas` are the root's direct children.
        //   (2) "Official" (what mindolph + mindmup.com emit): the doc
        //       has `formatVersion` / `id: "root"` at the top, and the
        //       actual root topic lives under `ideas.<key>` (usually
        //       "1"). The top-level `title` is just a label.
        //
        // We detect (2) by the presence of `formatVersion` and unwrap
        // before delegating to the simplified walker.
        let rootDict: [String: Any]
        if dict["formatVersion"] != nil,
           let outerIdeas = dict["ideas"] as? [String: Any],
           let firstRootKey = outerIdeas.keys
                .compactMap({ key -> (Double, String)? in
                    guard let w = Double(key.trimmingCharacters(in: .whitespaces)) else { return nil }
                    return (w, key)
                })
                .min(by: { $0.0 < $1.0 })?.1,
           let inner = outerIdeas[firstRootKey] as? [String: Any] {
            rootDict = inner
        } else {
            rootDict = dict
        }

        let root = Topic(text: title(from: rootDict))
        map.root = root
        appendIdeas(from: rootDict, to: root, isRoot: true)
        return map
    }

    /// Walk the `ideas` dict on `dict`, sort keys by numeric weight, and
    /// append a child to `parent` per entry. When `isRoot`, negatively-
    /// ordered children are stamped as `leftSide=true` to preserve the
    /// Mindmup left/right layout convention.
    private static func appendIdeas(from dict: [String: Any], to parent: Topic, isRoot: Bool) {
        guard let ideas = dict["ideas"] as? [String: Any], !ideas.isEmpty else { return }
        let ordered = ideas.compactMap { (key, value) -> (Double, [String: Any])? in
            guard let v = value as? [String: Any] else { return nil }
            let weight = Double(key.trimmingCharacters(in: .whitespaces)) ?? 0
            return (weight, v)
        }.sorted { $0.0 < $1.0 }

        for (weight, ideaDict) in ordered {
            let child = parent.addChild(text: title(from: ideaDict))
            if isRoot, weight < 0 {
                child.setAttribute(TopicAttribute.leftSide, "true")
            }
            appendIdeas(from: ideaDict, to: child, isRoot: false)
        }
    }

    /// Pull the `title` field from an idea dict, falling back gracefully
    /// for missing / non-string values so a malformed leaf doesn't sink
    /// the whole import.
    static func title(from dict: [String: Any]) -> String {
        if let s = dict["title"] as? String { return s }
        if let n = dict["title"] as? NSNumber { return n.stringValue }
        return ""
    }
}
