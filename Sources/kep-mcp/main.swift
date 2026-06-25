import Foundation
import KepBridge

// kep-mcp — a Model Context Protocol server (stdio, newline-delimited JSON-RPC)
// that bridges an external agent to the RUNNING kep app. It forwards MCP
// tools/list + tools/call to the app's Unix-socket bridge, so the tool set is
// exactly kep's own agent tools and edits hit the live session.
//
// Socket path: --socket <path> arg or KEP_SOCKET env, else the default.

let socketPath: String = {
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--socket"), i + 1 < args.count { return args[i + 1] }
    if let env = ProcessInfo.processInfo.environment["KEP_SOCKET"], !env.isEmpty { return env }
    return KepBridge.defaultSocketPath
}()

func bridge(_ request: BridgeRequest) -> BridgeResponse {
    guard let data = try? JSONEncoder().encode(request),
          let json = String(data: data, encoding: .utf8),
          let line = try? KepBridgeClient.send(json, socketPath: socketPath),
          let rd = line.data(using: .utf8),
          let response = try? JSONDecoder().decode(BridgeResponse.self, from: rd) else {
        return .failure("kep app not reachable (is it running with the bridge enabled?)")
    }
    return response
}

func write(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}

func respond(id: Any?, result: [String: Any]) {
    write(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
}
func respondError(id: Any?, code: Int, _ message: String) {
    write(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]])
}

func handle(_ msg: [String: Any]) {
    let id = msg["id"]
    guard let method = msg["method"] as? String else { return }
    switch method {
    case "initialize":
        respond(id: id, result: [
            "protocolVersion": "2024-11-05",
            "capabilities": ["tools": [:]],
            "serverInfo": ["name": "kep", "version": "0.1.0"],
        ])
    case "notifications/initialized", "notifications/cancelled":
        break   // notifications have no id; nothing to return
    case "tools/list":
        let r = bridge(BridgeRequest(method: "tools/list"))
        let tools: [[String: Any]] = (r.tools ?? []).map { t in
            let schema = (t.parametersJSON.data(using: .utf8))
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                ?? ["type": "object", "properties": [:]]
            return ["name": t.name, "description": t.description, "inputSchema": schema]
        }
        respond(id: id, result: ["tools": tools])
    case "tools/call":
        let params = msg["params"] as? [String: Any] ?? [:]
        guard let name = params["name"] as? String else {
            respondError(id: id, code: -32602, "missing tool name"); return
        }
        let argsObj = params["arguments"] as? [String: Any] ?? [:]
        let argsJSON = (try? JSONSerialization.data(withJSONObject: argsObj))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let r = bridge(BridgeRequest(method: "tools/call", name: name, arguments: argsJSON))
        if r.ok {
            respond(id: id, result: ["content": [["type": "text", "text": r.result ?? ""]]])
        } else {
            respond(id: id, result: ["content": [["type": "text", "text": r.error ?? "error"]],
                                     "isError": true])
        }
    default:
        if id != nil { respondError(id: id, code: -32601, "method not found: \(method)") }
    }
}

// stdio read loop: one JSON-RPC message per line.
while let line = readLine(strippingNewline: true) {
    guard !line.isEmpty, let data = line.data(using: .utf8),
          let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
    handle(msg)
}
