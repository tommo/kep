import SwiftUI
import MindoBase

/// Runner panel for Lua automation scripts. Edits the active mind map through
/// the `mindo` API; shows the return value or the error. Real Lua — loops,
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
                Text("automates the active mind map via the `mindo` API")
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
        if !ran { return "⌘↩ to run. Topics are handles; see mindo.all(), mindo.addChild, mindo.setAttr, mindo.backlinks…" }
        return output.isEmpty ? "(done)" : output
    }

    private func run() {
        let result = session.runActiveLuaScript(script)
        ran = true
        errorText = result.error
        output = result.output
    }

    static let example = """
    -- Color every node whose text contains "TODO".
    local n = 0
    for _, id in ipairs(mindo.all()) do
      if string.find(mindo.text(id), "TODO") then
        mindo.setAttr(id, "fillColor", "#ffcdd2")
        n = n + 1
      end
    end
    return n .. " node(s) flagged"
    """
}
