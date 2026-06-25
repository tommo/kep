import Foundation
import Compression

/// A minimal, read-only ZIP archive reader — just enough to pull named entries
/// out of mind-map bundle formats (`.xmind`, `.nm5`, …) without an external
/// dependency. Parses the central directory and inflates STORED (0) and
/// DEFLATE (8) entries via Apple's Compression framework (`COMPRESSION_ZLIB`
/// consumes raw RFC-1951 DEFLATE, which is exactly what ZIP method 8 stores).
/// Pure → unit-testable.
public struct ZipArchive {
    public struct Entry: Equatable, Sendable {
        public let path: String
        public let isDirectory: Bool
        let method: UInt16
        let compSize: Int
        let uncompSize: Int
        let localOffset: Int
    }

    private let bytes: [UInt8]
    public let entries: [Entry]

    public init?(data: Data) {
        let b = [UInt8](data)
        guard let eocd = Self.findEOCD(b) else { return nil }
        let count = Int(Self.u16(b, eocd + 10))
        let cdOffset = Int(Self.u32(b, eocd + 16))
        guard cdOffset <= b.count else { return nil }

        var p = cdOffset
        var found: [Entry] = []
        for _ in 0..<count {
            guard p + 46 <= b.count, Self.u32(b, p) == 0x02014b50 else { break }
            let method = Self.u16(b, p + 10)
            let compSize = Int(Self.u32(b, p + 20))
            let uncompSize = Int(Self.u32(b, p + 24))
            let nameLen = Int(Self.u16(b, p + 28))
            let extraLen = Int(Self.u16(b, p + 30))
            let commentLen = Int(Self.u16(b, p + 32))
            let localOffset = Int(Self.u32(b, p + 42))
            let nameStart = p + 46
            guard nameStart + nameLen <= b.count else { break }
            let name = String(decoding: b[nameStart..<nameStart + nameLen], as: UTF8.self)
            found.append(Entry(path: name, isDirectory: name.hasSuffix("/"),
                               method: method, compSize: compSize,
                               uncompSize: uncompSize, localOffset: localOffset))
            p = nameStart + nameLen + extraLen + commentLen
        }
        self.bytes = b
        self.entries = found
    }

    /// Decompressed bytes of the entry at `path`, or nil if absent/unsupported.
    public func data(for path: String) -> Data? {
        entries.first { $0.path == path }.flatMap(extract)
    }

    /// First entry whose path satisfies `predicate` (case-insensitive callers
    /// can lowercase), decompressed. Handy for "find content.json anywhere".
    public func firstData(where predicate: (String) -> Bool) -> Data? {
        entries.first { !$0.isDirectory && predicate($0.path) }.flatMap(extract)
    }

    private func extract(_ e: Entry) -> Data? {
        let lo = e.localOffset
        guard lo + 30 <= bytes.count, Self.u32(bytes, lo) == 0x04034b50 else { return nil }
        let nameLen = Int(Self.u16(bytes, lo + 26))
        let extraLen = Int(Self.u16(bytes, lo + 28))
        let dataStart = lo + 30 + nameLen + extraLen
        guard dataStart + e.compSize <= bytes.count else { return nil }
        let comp = Array(bytes[dataStart..<dataStart + e.compSize])
        switch e.method {
        case 0: return Data(comp)                                  // stored
        case 8: return Self.inflate(comp, expected: e.uncompSize)  // deflate
        default: return nil
        }
    }

    static func inflate(_ src: [UInt8], expected: Int) -> Data? {
        guard expected > 0 else { return Data() }
        guard !src.isEmpty else { return nil }
        var dst = [UInt8](repeating: 0, count: expected)
        let written = src.withUnsafeBufferPointer { sp in
            dst.withUnsafeMutableBufferPointer { dp in
                compression_decode_buffer(dp.baseAddress!, expected,
                                          sp.baseAddress!, src.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { return nil }
        return Data(dst[0..<written])
    }

    // MARK: - Little-endian readers / EOCD scan

    static func u16(_ b: [UInt8], _ o: Int) -> UInt16 {
        guard o + 1 < b.count else { return 0 }
        return UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 3 < b.count else { return 0 }
        return UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }

    /// Locate the End Of Central Directory record (sig 0x06054b50), scanning
    /// back from the end within the max comment window.
    static func findEOCD(_ b: [UInt8]) -> Int? {
        guard b.count >= 22 else { return nil }
        let minP = max(0, b.count - (65_557 + 22))
        var i = b.count - 22
        while i >= minP {
            if u32(b, i) == 0x06054b50 { return i }
            i -= 1
        }
        return nil
    }
}
