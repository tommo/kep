import Foundation
import KepBridge

// kep — command-line client for the running kep app's bridge socket.
//
//   kep tools                       list available tools (name + description)
//   kep call <tool> '<json-args>'   call a tool, print its text result
//   kep search <query>              sugar for: call search {"query": "..."}
//   kep eval <doc> '<lua>'          sugar for: call notebook_eval / add_csv_block
//
// Talks to the live app over the Unix socket, so it reflects unsaved editor
// state and the app updates its UI. Use --socket <path> to override.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func send(_ request: BridgeRequest, socket: String) -> BridgeResponse {
    guard let data = try? JSONEncoder().encode(request),
          let json = String(data: data, encoding: .utf8) else { fail("could not encode request") }
    do {
        let responseLine = try KepBridgeClient.send(json, socketPath: socket)
        guard let rd = responseLine.data(using: .utf8),
              let response = try? JSONDecoder().decode(BridgeResponse.self, from: rd) else {
            fail("bad response: \(responseLine)")
        }
        return response
    } catch {
        fail("can't reach kep — is the app running with the bridge enabled? (\(error))")
    }
}

var args = Array(CommandLine.arguments.dropFirst())
var socketPath = KepBridge.defaultSocketPath
if let i = args.firstIndex(of: "--socket"), i + 1 < args.count {
    socketPath = args[i + 1]
    args.removeSubrange(i...(i + 1))
}

guard let command = args.first else {
    fail("usage: kep <tools|call|search|eval> …   [--socket <path>]")
}
let rest = Array(args.dropFirst())

switch command {
case "tools":
    let r = send(BridgeRequest(method: "tools/list"), socket: socketPath)
    for t in r.tools ?? [] { print("\(t.name)\t\(t.description)") }

case "call":
    guard rest.count >= 1 else { fail("usage: kep call <tool> '<json-args>'") }
    let r = send(BridgeRequest(method: "tools/call", name: rest[0],
                               arguments: rest.count >= 2 ? rest[1] : "{}"),
                 socket: socketPath)
    if r.ok { print(r.result ?? "") } else { fail(r.error ?? "error") }

case "search":
    guard !rest.isEmpty else { fail("usage: kep search <query>") }
    let query = rest.joined(separator: " ")
    let argsJSON = #"{"query":"\#(query.replacingOccurrences(of: "\"", with: "\\\""))"}"#
    let r = send(BridgeRequest(method: "tools/call", name: "search", arguments: argsJSON), socket: socketPath)
    if r.ok { print(r.result ?? "") } else { fail(r.error ?? "error") }

default:
    fail("unknown command '\(command)' — try: tools, call, search")
}
