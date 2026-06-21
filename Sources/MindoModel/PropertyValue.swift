import Foundation

/// The typed kinds a node property can take. Phase 1 of the Typed Node
/// Properties keystone (#200). Pure model — no Topic/serializer coupling.
public enum PropertyType: String, CaseIterable, Sendable {
    case text
    case number
    case date
    case checkbox
    case list
    case topicRef
}

/// A typed node-property value. This is the in-memory *view*; on disk every
/// value still lives as a plain string in `Topic.attributes` (the serializer is
/// untouched — see [[project_typed_properties]]). `PropertyCodec` is the only
/// bridge between the two.
public enum PropertyValue: Equatable, Sendable {
    case text(String)
    case number(Double)
    case date(Date)
    case checkbox(Bool)
    case list([String])
    case topicRef(uid: String)

    public var kind: PropertyType {
        switch self {
        case .text:     return .text
        case .number:   return .number
        case .date:     return .date
        case .checkbox: return .checkbox
        case .list:     return .list
        case .topicRef: return .topicRef
        }
    }
}

/// The single authority for converting a `PropertyValue` to/from the plain
/// string stored in `Topic.attributes`. Encodings are canonical and chosen so
/// they round-trip losslessly through the existing `.mmd` `> ` attribute block
/// (no newlines, no trailing backticks — the substrate gaps from #211):
///   - text:     verbatim
///   - number:   shortest round-trippable decimal, no trailing `.0`
///   - date:     ISO-8601 `yyyy-MM-dd` (date-only / UTC midnight) or
///               `yyyy-MM-ddTHH:mm:ssZ` (instant, second precision)
///   - checkbox: `true` / `false`
///   - list:     compact JSON string array `["a","b"]`
///   - topicRef: the bare topic UID (matches `ExtraTopic.topicUidAttr`)
public enum PropertyCodec {

    // MARK: Encode (total)

    public static func encode(_ value: PropertyValue) -> String {
        switch value {
        case .text(let s):       return s
        case .number(let d):     return encodeNumber(d)
        case .checkbox(let b):   return b ? "true" : "false"
        case .topicRef(let uid): return uid
        case .date(let d):       return encodeDate(d)
        case .list(let items):   return encodeList(items)
        }
    }

    // MARK: Decode (partial — nil when `string` isn't valid for `type`)

    /// Decode `string` as `type`. `.text` and `.topicRef` always succeed; the
    /// strict types return nil when the string doesn't parse, so callers can
    /// fall back to `.text(string)` and never lose the raw value.
    public static func decode(_ string: String, as type: PropertyType) -> PropertyValue? {
        switch type {
        case .text:
            return .text(string)
        case .topicRef:
            return string.isEmpty ? nil : .topicRef(uid: string)
        case .number:
            guard let d = Double(string), d.isFinite else { return nil }
            return .number(d)
        case .checkbox:
            switch string {
            case "true":  return .checkbox(true)
            case "false": return .checkbox(false)
            default:      return nil
            }
        case .date:
            return decodeDate(string).map(PropertyValue.date)
        case .list:
            return decodeList(string).map(PropertyValue.list)
        }
    }

    // MARK: - Number

    private static func encodeNumber(_ d: Double) -> String {
        // `String(Double)` is the shortest representation that round-trips
        // exactly; just drop a redundant `.0` so integers read as `3`, not `3.0`.
        var s = String(d)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return s
    }

    // MARK: - Date

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let instantFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        f.formatOptions = [.withInternetDateTime]   // yyyy-MM-ddTHH:mm:ssZ, no fractional
        return f
    }()

    private static func encodeDate(_ d: Date) -> String {
        // Emit date-only when the instant lands exactly on a UTC midnight,
        // otherwise a second-precision instant.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.hour, .minute, .second, .nanosecond], from: d)
        if c.hour == 0, c.minute == 0, c.second == 0, (c.nanosecond ?? 0) == 0 {
            return dateOnlyFormatter.string(from: d)
        }
        return instantFormatter.string(from: d)
    }

    private static func decodeDate(_ s: String) -> Date? {
        // DateFormatter is permissive with separators (it would accept
        // `2026/06/20`); require the parse to re-encode identically so only the
        // canonical ISO form is accepted.
        if s.contains("T") {
            guard let d = instantFormatter.date(from: s), instantFormatter.string(from: d) == s else { return nil }
            return d
        }
        guard let d = dateOnlyFormatter.date(from: s), dateOnlyFormatter.string(from: d) == s else { return nil }
        return d
    }

    // MARK: - List

    private static func encodeList(_ items: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: []),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    private static func decodeList(_ s: String) -> [String]? {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: []),
              let arr = obj as? [Any] else { return nil }
        // Reject mixed/non-string arrays so a stray JSON object isn't silently
        // coerced — only an array of strings is a valid list value.
        var out: [String] = []
        for el in arr {
            guard let str = el as? String else { return nil }
            out.append(str)
        }
        return out
    }
}

/// Best-effort *value-level* type inference: given only the raw stored string
/// (no declared schema yet), pick the most specific `PropertyValue` it parses
/// as. This is the default until vault-wide schema/supertags land (#200 later
/// phases) — a declared type, when present, will override this.
///
/// Order is most-specific → least, and `.text` is the always-succeeding floor
/// so inference is total and never loses the raw string:
///   checkbox (`true`/`false`) → list (JSON `[...]`) → date (ISO) →
///   number (finite) → text.
public enum PropertyInference {

    public static func infer(_ raw: String) -> PropertyValue {
        // Try the strict types in priority order via the codec (single source of
        // truth for parsing), falling back to verbatim text.
        for type in inferenceOrder {
            if let value = PropertyCodec.decode(raw, as: type) { return value }
        }
        return .text(raw)
    }

    /// The inferred kind for a raw string (convenience over `infer(_:).kind`).
    public static func inferType(_ raw: String) -> PropertyType { infer(raw).kind }

    /// `.text` is excluded here (it's the unconditional fallback) and
    /// `.topicRef` is excluded (any non-empty string would match it, which would
    /// shadow more-specific types — topic refs are only known via schema/extra).
    private static let inferenceOrder: [PropertyType] = [.checkbox, .list, .date, .number]
}
