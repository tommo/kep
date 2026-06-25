import SwiftUI
import KepBase

/// Runner panel for Lua automation scripts. Edits the active mind map through
/// the `kep` API; shows the return value or the error. Real Lua — loops,
/// string ops, the works.
struct LuaRunnerView: View {
    @Binding var session: AppSession
    @Environment(\.dismiss) private var dismiss

    @State private var script: String = LuaRunnerView.example
    @State private var output: String = ""
    @State private var errorText: String?
    @State private var ran = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "terminal").foregroundStyle(.purple)
                Text("Run Lua Script").font(.headline)
                Spacer()
                Text("automates the active mind map via the `kep` API")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            Divider()

            TextEditor(text: $script)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 220)

            Divider()
            ScrollView {
                Text(displayText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(errorText != nil ? Color.red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(height: 92)
            .background(Color.gray.opacity(0.06))

            Divider()
            HStack {
                Button("Run", systemImage: "play.fill") { run() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(10)
        }
        .frame(width: 580, height: 480)
    }

    private var displayText: String {
        if let errorText { return errorText }
        if !ran { return "⌘↩ to run. Topics are handles; see kep.all(), kep.addChild, kep.setAttr, kep.backlinks…" }
        return output.isEmpty ? "(done)" : output
    }

    private func run() {
        let result = session.runActiveLuaScript(script)
        ran = true
        errorText = result.error
        output = result.output
    }

    static let example = """
    -- Flag every "TODO" node red and attach a note. `kep.find` searches the
    -- whole tree; see also move / link / setNote / path / readDoc / backlinks.
    local hits = kep.find("TODO")
    for _, id in ipairs(hits) do
      kep.setAttr(id, "fillColor", "#ffcdd2")
      kep.setNote(id, "flagged by script")
    end
    return #hits .. " node(s) flagged"
    """
}
