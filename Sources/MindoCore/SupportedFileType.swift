import Foundation

/// File-type classification for routing files to editors. Mirrors `SupportFileTypes`.
public enum SupportedFileType: String, CaseIterable, Codable, Sendable {
    case mindMap = "mmd"
    case markdown = "md"
    case plantUML = "puml"
    case csv = "csv"
    case plainText = "txt"
    case jpeg = "jpg"
    case png = "png"

    public static func classify(url: URL) -> SupportedFileType? {
        let ext = url.pathExtension.lowercased()
        return SupportedFileType(rawValue: ext)
    }

    public static func classify(name: String) -> SupportedFileType? {
        let ext = (name as NSString).pathExtension.lowercased()
        return SupportedFileType(rawValue: ext)
    }

    public var isImage: Bool {
        self == .jpeg || self == .png
    }

    public var isText: Bool {
        switch self {
        case .mindMap, .markdown, .plantUML, .csv, .plainText: return true
        case .jpeg, .png: return false
        }
    }

    /// SF Symbol name to use when displaying this file type in lists, tabs, or
    /// the sidebar. Use `unknownSymbolName` for files we couldn't classify.
    public var sfSymbolName: String {
        switch self {
        case .mindMap: return "brain"
        case .markdown: return "text.alignleft"
        case .plantUML: return "rectangle.connected.to.line.below"
        case .csv: return "tablecells"
        case .plainText: return "doc.text"
        case .jpeg, .png: return "photo"
        }
    }

    public static let unknownSymbolName = "doc"
}
