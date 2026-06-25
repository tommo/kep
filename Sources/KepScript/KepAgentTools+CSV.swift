import Foundation

// CSV / spreadsheet cell editing for the agent. The spreadsheet model + formula
// engine live in KepCSV (which depends on KepScript), so the actual cell
// read/write is injected by the host via AgentToolEffects.csvCellValue /
// csvSetCell — these tools just resolve the doc name + dispatch.
extension KepAgentTools {
    static let csvDescriptors: [(name: String, description: String, parametersJSON: String)] = [
        ("read_csv_cell",
         "Read one cell of a CSV / spreadsheet document by A1 reference (e.g. B3). Returns its value, or the formula source if the cell holds a formula.",
         #"{"type":"object","properties":{"name":{"type":"string"},"cell":{"type":"string"}},"required":["name","cell"]}"#),
        ("set_csv_cell",
         "Set one cell of a CSV / spreadsheet document by A1 reference (e.g. B3) to a literal value or a formula (e.g. =A1+B1, =SUM(A1:A10)). Grows the sheet if the cell is past the current bounds. Writes the file on disk.",
         #"{"type":"object","properties":{"name":{"type":"string"},"cell":{"type":"string"},"value":{"type":"string"}},"required":["name","cell","value"]}"#),
        ("add_csv_block",
         "Add a named Lua 'sheet block' to a CSV/spreadsheet — a computation over the WHOLE table, shown in the editor's Sheet Blocks panel. The block's `return` value becomes the named result, referenceable from any cell as =block_name. Sheet API (on top of SUM/AVERAGE/…): cell(\"A1\"); col(\"A\") by column letter OR col(\"Header\") by header name; rows() (row tables keyed by header); nrows(); ncols(); sum/avg/count/min/max/median over arrays; print(...) for extra output. Example source: return avg(col(\"A\")). Persists to the file's sidecar.",
         #"{"type":"object","properties":{"name":{"type":"string"},"block_name":{"type":"string"},"source":{"type":"string"}},"required":["name","block_name","source"]}"#),
    ]

    func handleCSV(_ name: String, _ a: ToolArgs) -> String? {
        switch name {
        case "read_csv_cell":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            guard let cell = a.str("cell") else { return "error: missing 'cell'" }
            guard let url = documentURL(named: docName) else { return "not found" }
            guard let read = effects.csvCellValue else { return "error: CSV editing unavailable" }
            let v = read(url, cell) ?? ""
            return v.isEmpty ? "(empty)" : v

        case "set_csv_cell":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            guard let cell = a.str("cell") else { return "error: missing 'cell'" }
            let value = a.str("value") ?? ""   // empty clears the cell
            guard let url = documentURL(named: docName) else { return "not found" }
            guard let write = effects.csvSetCell else { return "error: CSV editing unavailable" }
            guard write(url, cell, value) else { return "error: couldn't set \(cell) (invalid A1 reference?)" }
            effects.changedFiles.insert(url)
            return "Set \(cell) in \(docName) to \(value.isEmpty ? "(empty)" : value)"

        case "add_csv_block":
            guard let docName = a.str("name") else { return "error: missing 'name'" }
            guard let blockName = a.str("block_name"), !blockName.isEmpty else { return "error: missing 'block_name'" }
            guard let source = a.str("source"), !source.isEmpty else { return "error: missing 'source'" }
            guard let url = documentURL(named: docName) else { return "not found" }
            guard let add = effects.csvAddBlock else { return "error: CSV editing unavailable" }
            let status = add(url, blockName, source)
            effects.changedFiles.insert(url)
            return "Added block '\(blockName)' to \(docName): \(status)"

        default:
            return nil
        }
    }
}
