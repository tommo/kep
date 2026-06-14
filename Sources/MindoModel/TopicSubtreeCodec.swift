import Foundation

/// JSON codec for a single Topic subtree. Powers ⌘C / ⌘V of a topic on
/// the canvas — the encoded payload travels through `NSPasteboard` under
/// the custom type `mindo.topic-subtree`. Stays in MindoModel so other
/// modules can use it without importing AppKit.
///
/// Wire format (stable so future versions can detect & migrate):
///
///     { "v": 1, "topic": <node> }
///
///     <node> = { "text": String, "attributes": {String:String},
///                "extras": [{ "type": String, "value": String }],
///                "snippets": {String:String}, "children": [<node>] }
public enum TopicSubtreeCodec {

    public static let pasteboardType = "com.mindo.topic-subtree"
    static let formatVersion = 1

    public enum CodecError: Error {
        case invalidJSON
        case wrongVersion
        case missingTopic
    }

    // MARK: - Encode

    public static func encode(_ topic: Topic) throws -> Data {
        let envelope: [String: Any] = ["v": formatVersion, "topic": serialize(topic)]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    /// Encode a forest (one or more topic subtrees) for a multi-selection
    /// copy: `{ "v":1, "topics":[<node>...] }`. Pair with `decodeForest`,
    /// which also accepts the single-topic `"topic"` form so older clipboard
    /// payloads still paste.
    public static func encodeForest(_ topics: [Topic]) throws -> Data {
        let envelope: [String: Any] = ["v": formatVersion, "topics": topics.map(serialize)]
        return try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
    }

    private static func serialize(_ topic: Topic) -> [String: Any] {
        var dict: [String: Any] = ["text": topic.text]
        if !topic.attributes.isEmpty {
            dict["attributes"] = topic.attributes
        }
        if !topic.extras.isEmpty {
            dict["extras"] = topic.extras.values.map { extra in
                ["type": extra.type.rawName, "value": extra.value]
            }
        }
        if !topic.codeSnippets.isEmpty {
            dict["snippets"] = topic.codeSnippets
        }
        if !topic.children.isEmpty {
            dict["children"] = topic.children.map(serialize)
        }
        return dict
    }

    // MARK: - Decode

    public static func decode(_ data: Data) throws -> Topic {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let envelope = any as? [String: Any] else {
            throw CodecError.invalidJSON
        }
        let version = (envelope["v"] as? Int) ?? 0
        guard version == formatVersion else { throw CodecError.wrongVersion }
        guard let topicDict = envelope["topic"] as? [String: Any] else { throw CodecError.missingTopic }
        return materialize(topicDict)
    }

    /// Decode a forest. Accepts the new `"topics"` array form *and* the
    /// legacy single `"topic"` form (returned as a one-element array), so a
    /// multi-select paste handler can use one code path for both.
    public static func decodeForest(_ data: Data) throws -> [Topic] {
        guard let any = try? JSONSerialization.jsonObject(with: data),
              let envelope = any as? [String: Any] else {
            throw CodecError.invalidJSON
        }
        let version = (envelope["v"] as? Int) ?? 0
        guard version == formatVersion else { throw CodecError.wrongVersion }
        if let dicts = envelope["topics"] as? [[String: Any]] {
            return dicts.map(materialize)
        }
        if let topicDict = envelope["topic"] as? [String: Any] {
            return [materialize(topicDict)]
        }
        throw CodecError.missingTopic
    }

    private static func materialize(_ dict: [String: Any]) -> Topic {
        let text = (dict["text"] as? String) ?? ""
        let topic = Topic(text: text)
        if let attrs = dict["attributes"] as? [String: String] {
            for (k, v) in attrs { topic.setAttribute(k, v) }
        }
        if let extras = dict["extras"] as? [[String: String]] {
            for entry in extras {
                guard let typeRaw = entry["type"], let value = entry["value"],
                      let type = ExtraType.from(token: typeRaw) else { continue }
                topic.setExtra(type.parseLoaded(value: value, attributes: topic.attributes))
            }
        }
        if let snippets = dict["snippets"] as? [String: String] {
            for (lang, body) in snippets { topic.putCodeSnippet(language: lang, body: body) }
        }
        if let children = dict["children"] as? [[String: Any]] {
            for childDict in children {
                topic.append(materialize(childDict))
            }
        }
        return topic
    }
}
