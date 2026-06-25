import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum BridgeSocketError: Error { case create, connect, bind, listen }

/// Fill a `sockaddr_un` with `path` and run `body` with a pointer to it.
private func withUnixAddr<R>(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let cap = MemoryLayout.size(ofValue: addr.sun_path)
    _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: cap) { dst in
            path.withCString { src in strncpy(dst, src, cap - 1) }
        }
    }
    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    return withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, len) }
    }
}

private func readLine(fd: Int32) -> String {
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(fd, &buf, buf.count)
        if n <= 0 { break }
        data.append(contentsOf: buf[0..<n])
        if data.contains(0x0A) { break }       // newline = end of message
    }
    return String(data: data, encoding: .utf8) ?? ""
}

private func writeAll(fd: Int32, _ s: String) {
    var line = s
    if !line.hasSuffix("\n") { line += "\n" }
    let bytes = Array(line.utf8)
    bytes.withUnsafeBytes { raw in
        var off = 0
        while off < raw.count {
            let n = write(fd, raw.baseAddress!.advanced(by: off), raw.count - off)
            if n <= 0 { break }
            off += n
        }
    }
}

/// One-shot client: connect, send a request line, read the response line, close.
/// Stateless so each agent tool call is independent.
public enum KepBridgeClient {
    public static func send(_ request: String, socketPath: String = KepBridge.defaultSocketPath) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeSocketError.create }
        defer { close(fd) }
        let rc = withUnixAddr(socketPath) { connect(fd, $0, $1) }
        guard rc == 0 else { throw BridgeSocketError.connect }
        writeAll(fd: fd, request)
        return readLine(fd: fd).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Accept loop on a background queue; each connection reads one request line,
/// runs `handler` (which the host hops to the main actor), writes one response.
public final class KepBridgeServer: @unchecked Sendable {
    private let path: String
    private let handler: (String) -> String
    private var listenFD: Int32 = -1
    private let queue = DispatchQueue(label: "kep.bridge.accept")

    public init(path: String = KepBridge.defaultSocketPath, handler: @escaping (String) -> String) {
        self.path = path
        self.handler = handler
    }

    @discardableResult
    public func start() -> Bool {
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        unlink(path)                                   // clear a stale socket
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { return false }
        let bound = withUnixAddr(path) { bind(listenFD, $0, $1) }
        guard bound == 0, listen(listenFD, 8) == 0 else { close(listenFD); return false }
        queue.async { [weak self] in self?.acceptLoop() }
        return true
    }

    public func stop() {
        if listenFD >= 0 { close(listenFD); listenFD = -1 }
        unlink(path)
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            let conn = accept(listenFD, nil, nil)
            if conn < 0 { break }
            let line = readLine(fd: conn)
            let response = handler(line)
            writeAll(fd: conn, response)
            close(conn)
        }
    }
}
