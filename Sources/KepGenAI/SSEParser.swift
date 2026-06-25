import Foundation

/// Server-Sent Events parser for OpenAI-style streaming bodies.
///
/// Each event is delimited by a blank line. Lines starting with `data: ` carry
/// the payload; the special payload `[DONE]` signals stream termination.
/// We keep a tiny state machine so callers can feed bytes incrementally.
public struct SSEParser {
    public struct Event: Equatable {
        public let data: String
        public init(data: String) { self.data = data }
    }

    private var buffer: String = ""

    public init() {}

    /// Append a chunk of bytes and emit any complete events.
    public mutating func append(_ chunk: String) -> [Event] {
        buffer.append(chunk)
        return drain()
    }

    public mutating func append(bytes: Data) -> [Event] {
        guard let s = String(data: bytes, encoding: .utf8) else { return [] }
        return append(s)
    }

    /// Flush remaining buffer at end-of-stream.
    public mutating func finish() -> [Event] {
        let events = drain(forceFinal: true)
        buffer = ""
        return events
    }

    private mutating func drain(forceFinal: Bool = false) -> [Event] {
        var events: [Event] = []
        while let range = buffer.range(of: "\n\n") {
            let block = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if let ev = Self.parseBlock(block) { events.append(ev) }
        }
        if forceFinal, !buffer.isEmpty, let ev = Self.parseBlock(buffer) {
            events.append(ev)
            buffer = ""
        }
        return events
    }

    private static func parseBlock(_ block: String) -> Event? {
        var data = ""
        for raw in block.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            // Skip comments (lines starting with `:`).
            if line.hasPrefix(":") { continue }
            if line.hasPrefix("data:") {
                let payload = line.dropFirst(5).drop(while: { $0 == " " })
                if !data.isEmpty { data.append("\n") }
                data.append(String(payload))
            }
        }
        return data.isEmpty ? nil : Event(data: data)
    }
}
