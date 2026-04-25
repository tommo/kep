import Foundation

/// Imports FreeMind / Freeplane `.mm` files (XML) into a `MindMap`.
///
/// FreeMind format (simplified):
/// ```
/// <map version="1.0.1">
///   <node TEXT="Root">
///     <node TEXT="Child" FOLDED="true">
///       <node TEXT="Leaf"/>
///     </node>
///   </node>
/// </map>
/// ```
///
/// Notable details we handle:
/// - `TEXT` attribute supplies the node title.
/// - Older Freeplane variants use `<richcontent TYPE="NODE">` with embedded
///   HTML for the title — we extract the visible text from the HTML.
/// - `FOLDED="true"` maps to the topic's `collapsed` attribute.
/// - `POSITION="left"` maps to `leftSide`.
/// - `<edge COLOR= STYLE= WIDTH=/>` lands on `edgeColor` / `edgeStyle` /
///   `edgeWidth` attributes (renderer side is parity card #44).
/// - `<icon BUILTIN="..."/>` lands on the `mmd.emoticon` attribute.
public enum FreemindImporter {

    public enum ImportError: Error, LocalizedError {
        case invalidXML(String)
        case noRootNode

        public var errorDescription: String? {
            switch self {
            case .invalidXML(let msg): return "Invalid FreeMind XML: \(msg)"
            case .noRootNode: return "FreeMind file has no root <node>"
            }
        }
    }

    public static func parse(_ xml: String) throws -> MindMap {
        guard let data = xml.data(using: .utf8) else {
            throw ImportError.invalidXML("non-UTF-8 input")
        }
        return try parse(data: data)
    }

    public static func parse(data: Data) throws -> MindMap {
        let parser = XMLParser(data: data)
        let delegate = FreemindParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            let msg = parser.parserError?.localizedDescription ?? "unknown XML error"
            throw ImportError.invalidXML(msg)
        }
        guard let root = delegate.rootTopic else {
            throw ImportError.noRootNode
        }
        let map = MindMap()
        map.root = root
        return map
    }
}

/// XMLParser delegate that builds a `Topic` tree as it walks `<node>`
/// elements. Tracks the current topic stack so nested `<node>` children are
/// attached to the right parent; pending `<richcontent>` blobs are
/// accumulated character-by-character and converted to plain text on close.
private final class FreemindParserDelegate: NSObject, XMLParserDelegate {
    var rootTopic: Topic?
    private var stack: [Topic] = []

    private var richContentBuffer: String?
    private var richContentDepth: Int = 0
    private var richContentTopic: Topic?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        // FreeMind uses uppercase attribute keys; Freeplane sometimes mixes
        // cases. Normalize for lookup.
        let attrs: [String: String] = Dictionary(uniqueKeysWithValues: attributeDict.map { ($0.key.uppercased(), $0.value) })

        switch elementName.lowercased() {
        case "node":
            let text = attrs["TEXT"] ?? ""
            let topic = Topic(text: text)
            if let folded = attrs["FOLDED"], folded.lowercased() == "true" {
                topic.setAttribute(TopicAttribute.collapsed, "true")
            }
            if let position = attrs["POSITION"], position.lowercased() == "left" {
                topic.setAttribute(TopicAttribute.leftSide, "true")
            }
            if let parent = stack.last {
                parent.append(topic)
            } else {
                rootTopic = topic
            }
            stack.append(topic)

        case "edge":
            // <edge COLOR="#990000" STYLE="bezier" WIDTH="thin"/> attaches to
            // the enclosing node. Capture so a future renderer can honor it
            // and a future writer can round-trip the attributes.
            if let topic = stack.last {
                if let color = attrs["COLOR"] {
                    topic.setAttribute(TopicAttribute.edgeColor, color)
                }
                if let style = attrs["STYLE"] {
                    topic.setAttribute(TopicAttribute.edgeStyle, style)
                }
                if let width = attrs["WIDTH"] {
                    topic.setAttribute(TopicAttribute.edgeWidth, width)
                }
            }

        case "icon":
            // <icon BUILTIN="bell"/> — FreeMind icon name. Surface as the
            // mmd.emoticon attribute so the existing renderer can pick it
            // up once emoticon rendering lands (parity card #44).
            if let topic = stack.last, let name = attrs["BUILTIN"] {
                topic.setAttribute(TopicAttribute.emoticon, name)
            }

        case "richcontent":
            if let type = attrs["TYPE"]?.uppercased(), type == "NODE", let topic = stack.last {
                richContentBuffer = ""
                richContentDepth = 0
                richContentTopic = topic
            }

        default:
            // Inside a <richcontent> block, count nested HTML tags so we know
            // when to stop collecting text.
            if richContentBuffer != nil { richContentDepth += 1 }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard richContentBuffer != nil else { return }
        richContentBuffer? += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName.lowercased() {
        case "node":
            _ = stack.popLast()

        case "richcontent":
            if let body = richContentBuffer, let topic = richContentTopic {
                let text = body
                    .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    // Override the TEXT attribute when richcontent supplies a
                    // title — Freeplane uses richcontent in place of TEXT.
                    topic.text = text
                }
            }
            richContentBuffer = nil
            richContentTopic = nil
            richContentDepth = 0

        default:
            if richContentBuffer != nil, richContentDepth > 0 { richContentDepth -= 1 }
        }
    }
}
