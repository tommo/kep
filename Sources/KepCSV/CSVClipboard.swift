import Foundation

/// Serialize / parse the cell-block clipboard wire format.
///
/// DELIBERATE FORMAT CHOICE: TSV — tab between columns, `\n` between rows —
/// rather than javamind's lossy "copy with `, ` / parse with bare `,`"
/// asymmetry (which injected a leading space into every column after the
/// first). TSV is also what Excel / Numbers put on the pasteboard, so blocks
/// round-trip with spreadsheets. A field containing a tab, CR, LF, or a
/// leading/trailing double-quote is wrapped in double-quotes with internal
/// quotes doubled, so the round-trip is lossless. Commas are NOT special
/// here (tab is the separator), unlike `CSVDocument.serialize`.
///
/// Pure strings only — no NSPasteboard — so it's fully unit-testable.
public enum CSVClipboard {

    public static func serialize(_ block: CSVBlock) -> String {
        block.cells
            .map { row in row.map(escape).joined(separator: "\t") }
            .joined(separator: "\n")
    }

    /// Parse clipboard text into a block. A SINGLE pass over the whole text
    /// tracks quote state, splitting fields on the chosen separator and
    /// records on unquoted newlines — so a quoted field may itself contain
    /// separators and newlines without being torn apart.
    ///
    /// Separator selection: if the text has an unquoted TAB anywhere it's
    /// treated as TSV (our own format, and what Excel/Numbers emit); else
    /// fields split on COMMA, so an external comma-CSV paste lands in columns
    /// instead of one cell per line. Because our own `serialize` quotes
    /// commas, an internal single-column block with comma values still
    /// round-trips (the quoted comma is preserved, not split).
    public static func parse(_ text: String) -> CSVBlock {
        guard !isBlankOrSeparators(text) else { return CSVBlock(cells: []) }
        // Normalize line endings so \r\n / \r record breaks behave like \n.
        let chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n")
                              .replacingOccurrences(of: "\r", with: "\n"))
        let separator: Character = hasUnquotedTab(chars) ? "\t" : ","
        var rows: [[String]] = []
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var fieldStartedQuoted = false
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        current.append("\"")   // doubled → literal quote
                        i += 2
                        continue
                    }
                    inQuotes = false           // closing quote
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" && current.isEmpty && !fieldStartedQuoted {
                inQuotes = true
                fieldStartedQuoted = true
            } else if ch == separator {
                fields.append(current); current = ""; fieldStartedQuoted = false
            } else if ch == "\n" {
                fields.append(current); current = ""; fieldStartedQuoted = false
                rows.append(fields); fields = []
            } else {
                current.append(ch)
            }
            i += 1
        }
        // Flush the trailing field/record (no terminating newline).
        fields.append(current)
        rows.append(fields)
        return CSVBlock(cells: rows)
    }

    /// Does the text contain a TAB outside of a quoted field? Drives the
    /// TSV-vs-comma separator choice.
    private static func hasUnquotedTab(_ chars: [Character]) -> Bool {
        var inQuotes = false
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { i += 2; continue }
                    inQuotes = false
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == "\t" {
                return true
            }
            i += 1
        }
        return false
    }

    // MARK: - Field encoding

    /// Quote a field when it contains a tab, newline, double-quote, OR a
    /// comma. The comma rule matters because `parse` may use comma as the
    /// separator (external CSV); quoting keeps an internal comma-bearing cell
    /// from being split on the round trip.
    private static func escape(_ field: String) -> String {
        let needsQuoting = field.contains("\t") || field.contains("\n")
            || field.contains("\r") || field.contains("\"") || field.contains(",")
        guard needsQuoting else { return field }
        let doubled = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(doubled)\""
    }

    private static func isBlankOrSeparators(_ text: String) -> Bool {
        text.allSatisfy { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }
    }
}
