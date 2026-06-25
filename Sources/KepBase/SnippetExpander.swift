import Foundation

/// Expands `${name}` placeholders inside snippet bodies before insertion.
/// Mirrors the role of `TemplateUtils.format` from `mindolph-core`, scoped
/// to the variables a user inserting a snippet usually wants:
///
/// - `${date}`     — today's date, ISO-style `YYYY-MM-DD`
/// - `${time}`     — local time, 24-hour `HH:mm`
/// - `${datetime}` — combined `YYYY-MM-DD HH:mm`
/// - `${user}`     — `NSFullUserName()` (account display name)
/// - `${filename}` — current document's filename without extension; empty when unsaved
/// - `${title}`    — current mindmap's root topic text; empty for non-mindmap docs
///
/// Unknown `${name}` placeholders pass through unchanged so the user can
/// still type literal `${foo}` in a snippet body.
public enum SnippetExpander {

    /// Per-insertion context — defaults to "no document context" so a
    /// caller without filename/title information can still expand the
    /// time/date/user variables.
    public struct Context: Sendable {
        public var filename: String
        public var title: String
        public var date: Date
        public init(filename: String = "", title: String = "", date: Date = Date()) {
            self.filename = filename
            self.title = title
            self.date = date
        }
    }

    private static func formatter(_ fmt: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = fmt
        return f
    }
    private static let dateFmt = formatter("yyyy-MM-dd")
    private static let timeFmt = formatter("HH:mm")
    private static let datetimeFmt = formatter("yyyy-MM-dd HH:mm")

    public static func expand(_ template: String, context: Context = Context()) -> String {
        guard template.contains("${") else { return template }
        let values: [String: String] = [
            "date":     dateFmt.string(from: context.date),
            "time":     timeFmt.string(from: context.date),
            "datetime": datetimeFmt.string(from: context.date),
            "user":     NSFullUserName(),
            "filename": context.filename,
            "title":    context.title,
        ]
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "${\(key)}", with: value)
        }
        return result
    }
}
