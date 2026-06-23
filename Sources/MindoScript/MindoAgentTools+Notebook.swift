import Foundation

/// Research-Notebook authoring tools — let the agent build the open notebook as
/// it researches: write findings as prose, and run Lua queries as code cells
/// (seeing their output). Only offered when a notebook is the active document
/// (the host wires `effects.notebookAddProse` / `notebookRunCode`).
extension MindoAgentTools {
    static let notebookDescriptors: [(name: String, description: String, parametersJSON: String)] = [
        ("notebook_add_note",
         "Append a prose cell (Markdown) to the current research notebook — use for findings, explanations, and the narrative argument. Cite sources inline.",
         #"{"type":"object","properties":{"text":{"type":"string"}},"required":["text"]}"#),
        ("notebook_add_code",
         "Append a Lua code cell to the notebook, run it against the `mindo` API + knowledge base, and return its output. Use to compute/verify a claim. The output is also shown in the notebook beneath the cell. Tip: assign results to NAMED globals (e.g. `params = {...}`) so later cells — and you — can reuse them.",
         #"{"type":"object","properties":{"code":{"type":"string"}},"required":["code"]}"#),
        ("notebook_eval",
         "Evaluate a Lua snippet in the notebook's LIVE shared session and return its value — for INSPECTING data that code cells already computed (e.g. `return #extraction`, `return docs[1]`, `return params.dose`). Does NOT add a cell to the notebook. Use notebook_add_code instead when the code should appear as part of the document.",
         #"{"type":"object","properties":{"code":{"type":"string"}},"required":["code"]}"#),
    ]

    func handleNotebook(_ name: String, _ a: ToolArgs) -> String? {
        switch name {
        case "notebook_add_note":
            guard let text = a.str("text") else { return "error: missing 'text'" }
            guard let add = effects.notebookAddProse else { return "error: no notebook is open" }
            add(text)
            return "added a note to the notebook"
        case "notebook_add_code":
            guard let code = a.str("code") else { return "error: missing 'code'" }
            guard let run = effects.notebookRunCode else { return "error: no notebook is open" }
            let output = run(code)
            return output.isEmpty ? "ran the cell (no output)" : "cell output:\n\(output)"
        case "notebook_eval":
            guard let code = a.str("code") else { return "error: missing 'code'" }
            guard let eval = effects.notebookEval else { return "error: no notebook is open" }
            let value = eval(code)
            return value.isEmpty ? "(no value)" : value
        default:
            return nil
        }
    }
}
