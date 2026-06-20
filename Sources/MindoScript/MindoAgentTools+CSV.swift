import Foundation

// CSV / spreadsheet cell editing for the agent. The spreadsheet model + formula
// engine live in MindoCSV (which depends on MindoScript), so the actual cell
// read/write is injected by the host via AgentToolEffects.csvCellValue /
// csvSetCell — these tools just resolve the doc name + dispatch.
extension MindoAgentTools {
    static let csvDescriptors: [(name: String, description: String, parametersJSON: String)] = [
        ("read_csv_cell",
         "Read one cell of a CSV / spreadsheet document by A1 reference (e.g. B3). Returns its value, or the formula source if the cell holds a formula.",
         #"{"type":"object","properties":{"name":{"type":"string"},"cell":{"type":"string"}},"required":["name","cell"]}"#),
        ("set_csv_cell",
         "Set one cell of a CSV / spreadsheet document by A1 reference (e.g. B3) to a literal value or a formula (e.g. =A1+B1, =SUM(A1:A10)). Grows the sheet if the cell is past the current bounds. Writes the file on disk.",
         #"{"type":"object","properties":{"name":{"type":"string"},"cell":{"type":"string"},"value":{"type":"string"}},"required":["name","cell","value"]}"#),
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

        default:
            return nil
        }
    }
}
