import Foundation

/// Wire protocol for the kep local bridge: one JSON request per line, one JSON
/// response per line, over a Unix-domain socket. Deliberately minimal (not full
/// JSON-RPC) — the MCP server translates the MCP protocol onto this.

public struct BridgeToolDescriptor: Codable, Sendable {
    public let name: String
    public let description: String
    /// JSON Schema for the tool's arguments, as a raw JSON string (the app
    /// already stores it this way; the MCP server parses it into `inputSchema`).
    public let parametersJSON: String

    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

public struct BridgeRequest: Codable, Sendable {
    public let method: String          // "tools/list" | "tools/call"
    public let name: String?           // tool name (tools/call)
    public let arguments: String?      // JSON-encoded arguments (tools/call)

    public init(method: String, name: String? = nil, arguments: String? = nil) {
        self.method = method
        self.name = name
        self.arguments = arguments
    }
}

public struct BridgeResponse: Codable, Sendable {
    public let ok: Bool
    public let result: String?                     // tool text output (tools/call)
    public let tools: [BridgeToolDescriptor]?      // tool list (tools/list)
    public let error: String?

    public init(ok: Bool, result: String? = nil,
                tools: [BridgeToolDescriptor]? = nil, error: String? = nil) {
        self.ok = ok
        self.result = result
        self.tools = tools
        self.error = error
    }

    public static func failure(_ message: String) -> BridgeResponse {
        BridgeResponse(ok: false, error: message)
    }
}

/// Decodes a request line, routes it through the host closures, encodes the
/// response line. Pure + synchronous so it's unit-testable; the host's closures
/// are responsible for hopping to the main actor (so they're not `@Sendable` —
/// they capture the app session and run inside the server's per-connection call).
public struct BridgeDispatcher {
    public let listTools: () -> [BridgeToolDescriptor]
    public let call: (_ name: String, _ argumentsJSON: String) -> String

    public init(listTools: @escaping () -> [BridgeToolDescriptor],
                call: @escaping (_ name: String, _ argumentsJSON: String) -> String) {
        self.listTools = listTools
        self.call = call
    }

    public func handle(_ request: BridgeRequest) -> BridgeResponse {
        switch request.method {
        case "tools/list":
            return BridgeResponse(ok: true, tools: listTools())
        case "tools/call":
            guard let name = request.name, !name.isEmpty else {
                return .failure("tools/call: missing 'name'")
            }
            return BridgeResponse(ok: true, result: call(name, request.arguments ?? "{}"))
        default:
            return .failure("unknown method '\(request.method)'")
        }
    }

    /// Decode → handle → encode. Always returns a valid response line.
    public func handleLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let request = try? JSONDecoder().decode(BridgeRequest.self, from: data) else {
            return Self.encode(.failure("malformed request"))
        }
        return Self.encode(handle(request))
    }

    public static func encode(_ response: BridgeResponse) -> String {
        guard let data = try? JSONEncoder().encode(response),
              let s = String(data: data, encoding: .utf8) else {
            return #"{"ok":false,"error":"encode failed"}"#
        }
        return s
    }
}

public enum KepBridge {
    /// The default socket path. Under the existing "Mindo" app-support dir (the
    /// internal id stays "Mindo"; only user-facing names are "kep").
    public static var defaultSocketPath: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return (base?.appendingPathComponent("Mindo/kep-bridge.sock").path)
            ?? NSTemporaryDirectory() + "kep-bridge.sock"
    }
}
