import Foundation

/// Emits a mindmap as a Mindmup `.mup` JSON document. Mirrors mindolph's
/// `MindmupExporter` for the common case (title, hierarchy, notes,
/// link/file extras as an HTML attachment, leftSide-aware ordering keys).
///
/// Round-trips with our `MindmupImporter`: keys in `ideas` are signed
/// integer weights (negative = left-of-root child), `title` is the
/// topic text, `note` lives under `attr.note.text`.
///
/// Skipped vs the Java version: jump-link table (mindolph stamps a
/// `links: [...]` array for ExtraTopic transitions) and embedded image
/// rendering — those need NSImage roundtripping and aren't required to
/// re-import the same map back.
public enum MindmupExporter {

    public static func export(_ map: MindMap) -> String {
        var counter = 1
        let rootObj: [String: Any]
        if let root = map.root {
            let rootIdea = encodeTopic(root, isRoot: true, counter: &counter)
            rootObj = [
                "formatVersion": 3,
                "id": "root",
                "ideas": ["1": rootIdea],
                "title": root.text,
            ]
        } else {
            rootObj = [
                "formatVersion": 3,
                "id": "root",
                "ideas": [String: Any](),
                "title": "Empty map",
            ]
        }
        // `prettyPrinted + sortedKeys` so the output diff-friendly. The
        // Java exporter doesn't sort but our consumers (tests, file
        // diffs) benefit more from determinism than from byte-for-byte
        // parity with Java.
        guard let data = try? JSONSerialization.data(
            withJSONObject: rootObj,
            options: [.prettyPrinted, .sortedKeys]
        ), let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private static func encodeTopic(_ topic: Topic, isRoot: Bool, counter: inout Int) -> [String: Any] {
        var obj: [String: Any] = [
            "title": topic.text,
            "id": counter,
        ]
        counter += 1

        var attr: [String: Any] = [:]
        if let note = topic.extra(.note) as? ExtraNote, !note.text.isEmpty {
            attr["note"] = ["index": 3, "text": note.text]
        }
        if !attr.isEmpty {
            obj["attr"] = attr
        }

        // link/file extras live in `attachment.content` as a small HTML
        // fragment — same shape mindolph emits so a round-trip through
        // mindmup.com keeps the URLs visible.
        let link = topic.extra(.link) as? ExtraLink
        let file = topic.extra(.file) as? ExtraFile
        if (link?.uri.isEmpty == false) || (file?.uri.isEmpty == false) {
            obj["attachment"] = [
                "contentType": "text/html",
                "content": attachmentHTML(link: link, file: file),
            ]
        }

        if !topic.children.isEmpty {
            var ideas: [String: Any] = [:]
            // Root children with `leftSide=true` get negative keys per
            // mindmup convention; everything else increments from 1.
            var leftCounter = 0
            var rightCounter = 0
            for child in topic.children {
                let onLeft = isRoot && (child.attributes[TopicAttribute.leftSide] == "true")
                let key: String
                if onLeft {
                    leftCounter -= 1
                    key = String(leftCounter)
                } else {
                    rightCounter += 1
                    key = String(rightCounter)
                }
                ideas[key] = encodeTopic(child, isRoot: false, counter: &counter)
            }
            obj["ideas"] = ideas
        }
        return obj
    }

    static func attachmentHTML(link: ExtraLink?, file: ExtraFile?) -> String {
        var out = ""
        if let f = file, !f.uri.isEmpty {
            out += "FILE: <a href=\"\(f.uri)\">\(f.uri)</a><br>"
        }
        if let l = link, !l.uri.isEmpty {
            out += "LINK: <a href=\"\(l.uri)\">\(l.uri)</a><br>"
        }
        return out
    }
}
