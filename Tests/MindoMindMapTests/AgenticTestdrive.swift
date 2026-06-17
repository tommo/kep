import XCTest
import MindoGenAI
import MindoModel

/// Agentic test-drive: author a comprehensive, interlinked example docset by
/// driving Mindo's *real* GenAI engine headlessly — the same `LLMProvider` +
/// `LLMInput` the in-app `AIGeneratePane` uses, just without the GUI. This is a
/// dogfooding harness, NOT a unit test: it is skipped unless
/// `MINDO_AI_TESTDRIVE=1` and a `DEEPSEEK_API_KEY` are present, since it makes
/// real network calls and writes files into `Examples/` in the repo.
///
///   MINDO_AI_TESTDRIVE=1 swift test --filter AgenticTestdrive 2>&1
///
/// Every doc's *content* is authored by the in-app engine; the harness only
/// crafts prompts (mirroring the pane) and saves the result — what the app's
/// `applyAIResult` + save would do. The mind map is built the way the app does
/// it (flat child topics under the root via the same logic, then serialized by
/// Mindo's own `MindMap.write()`), so the gaps are real, not simulated.
final class AgenticTestdrive: XCTestCase {

    private struct DocTask {
        let file: String
        let prompt: String
        let validate: (String) -> String?   // nil == ok, else reason
    }

    func testAuthorEspressoDocset() async throws {
        guard ProcessInfo.processInfo.environment["MINDO_AI_TESTDRIVE"] == "1" else {
            throw XCTSkip("Set MINDO_AI_TESTDRIVE=1 to run the live agentic test-drive.")
        }
        let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? ""
        try XCTSkipIf(key.isEmpty, "DEEPSEEK_API_KEY not set.")

        // The exact provider the app builds for DeepSeek.
        let meta = ProviderMeta(apiKey: key, endpoint: GenAIProviderID.deepSeek.defaultEndpoint)
        let model = ModelMeta(name: "deepseek-chat", maxTokens: 8192)
        let provider = try XCTUnwrap(
            LLMProviderFactory.create(providerID: .deepSeek, meta: meta, model: model)
        )

        let outDir = Self.repoRoot.appendingPathComponent("Examples/espresso-kb", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        // Link targets are spelled out IN the prompt — the in-app tool feeds the
        // model no workspace/corpus context, so a KB-aware docset can only be
        // produced by hand-injecting filenames here. (Evaluation finding.)
        let mdRule = "Output only the document body — no code fences, no preamble, no 'Here is'."
        let textTasks: [DocTask] = [
            DocTask(file: "Home.md", prompt: """
                Write a concise Markdown index page titled "Espresso Knowledge Base". One short
                intro paragraph, then a bulleted map linking each note with Obsidian-style wiki
                links: [[Extraction]], [[Grind]], [[Brewing Process]], [[Bean Origins]],
                [[Espresso Map]]. \(mdRule)
                """, validate: { out in
                    let need = ["[[Extraction]]", "[[Grind]]", "[[Brewing Process]]", "[[Bean Origins]]"]
                    let miss = need.filter { !out.contains($0) }
                    return miss.isEmpty ? nil : "missing wiki links: \(miss.joined(separator: ", "))"
                }),
            DocTask(file: "Extraction.md", prompt: """
                Write a focused Markdown note titled "Extraction" for an espresso knowledge base:
                what extraction is, under- vs over-extraction with tasting signs, and the key
                variables. Include a short Markdown table of the main variables and typical
                ranges. End with a "See also" line linking [[Grind]] and [[Home]]. \(mdRule)
                """, validate: { $0.contains("[[Grind]]") && $0.contains("|") ? nil : "no [[Grind]] link or table" }),
            DocTask(file: "Grind.md", prompt: """
                Write a Markdown note titled "Grind" for an espresso knowledge base: why grind
                size matters, how it changes extraction and shot time, and dialing-in advice.
                End with a "See also" line linking [[Extraction]] and [[Home]]. \(mdRule)
                """, validate: { $0.contains("[[Extraction]]") ? nil : "no [[Extraction]] link" }),
            DocTask(file: "Brewing Process.puml", prompt: """
                Generate PlantUML source for an activity diagram of pulling an espresso shot:
                dose, distribute, tamp, lock portafilter, start pump, watch extraction, stop at
                target yield, evaluate; include a decision on whether the shot ran too fast/slow
                that loops back to adjust the grind. Output ONLY valid PlantUML from @startuml to
                @enduml — no commentary, no code fences.
                """, validate: { $0.contains("@startuml") && $0.contains("@enduml") ? nil : "missing @startuml/@enduml" }),
            DocTask(file: "Bean Origins.csv", prompt: """
                Output a CSV with a header row of 10 notable espresso bean origins. Columns:
                Origin,Region,Typical Roast,Flavor Notes,Body. Use real coffee-producing origins.
                Output ONLY the CSV — no code fences, no commentary.
                """, validate: { out in
                    let rows = out.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    guard let h = rows.first, h.contains(",") else { return "no comma header" }
                    return rows.count >= 6 ? nil : "only \(rows.count) rows"
                }),
        ]

        var report: [String] = [
            "# Agentic test-drive report", "",
            "Engine: DeepSeek `deepseek-chat` via Mindo's `LLMProvider` — the same path `AIGeneratePane` drives.",
            "Authored \(textTasks.count) text docs + 1 mind map. Each entry: validation · size · output tokens · latency.", "",
        ]

        for task in textTasks {
            let input = LLMInput(providerID: GenAIProviderID.deepSeek.rawValue, model: model.name,
                                 text: task.prompt, temperature: 0.7, maxTokens: model.maxTokens, isStreaming: false)
            let start = Date()
            let partial = try await provider.predict(input)
            let elapsed = Date().timeIntervalSince(start)
            let body = Self.stripCodeFence(partial.text.trimmingCharacters(in: .whitespacesAndNewlines))
            let problem = task.validate(body)
            try (body + "\n").write(to: outDir.appendingPathComponent(task.file), atomically: true, encoding: .utf8)
            let status = problem == nil ? "✅ ok" : "⚠️ \(problem!)"
            report.append("- **\(task.file)** — \(status) · \(body.count) chars · \(partial.outputTokens) tok · \(String(format: "%.1fs", elapsed))")
            print("[TESTDRIVE] \(task.file): \(status), \(body.count) chars, \(partial.outputTokens) tok, \(String(format: "%.1fs", elapsed))")
        }

        // Mind map via the REAL in-app path: childTopic mode generates lines, each
        // line becomes a flat child of the root (mirrors AppSession.appendLinesAsChildren),
        // then Mindo serializes it. This is the ceiling of what the tool can author.
        let mmPrompt = """
            For a mind map whose root topic is "Espresso", generate 8 to 12 child topics covering
            equipment, variables, the brewing process, and bean origins. Output one short topic per
            line — no numbering, no bullets, no indentation, no extra prose.
            """
        let mmInput = LLMInput(providerID: GenAIProviderID.deepSeek.rawValue, model: model.name,
                               text: mmPrompt, temperature: 0.7, maxTokens: model.maxTokens, isStreaming: false)
        let mmStart = Date()
        let mmPartial = try await provider.predict(mmInput)
        let mmElapsed = Date().timeIntervalSince(mmStart)
        let map = MindMap(root: Topic(text: "Espresso"))
        let parent = map.root!
        var childCount = 0
        for line in Self.stripCodeFence(mmPartial.text).split(whereSeparator: { $0 == "\n" }) {
            let t = line.trimmingCharacters(in: .whitespaces)
            // The app's append logic is verbatim line text; strip stray markers the
            // model adds anyway so the example file isn't ugly. (Finding: the app does NOT.)
            let clean = t.drop(while: { "-*•0123456789. ".contains($0) }).trimmingCharacters(in: .whitespaces)
            if clean.isEmpty { continue }
            _ = parent.addChild(text: clean)
            childCount += 1
        }
        let mmd = map.write()
        try mmd.write(to: outDir.appendingPathComponent("Espresso Map.mmd"), atomically: true, encoding: .utf8)
        // Round-trip through Mindo's own parser to prove the example opens.
        let reopens = (try? MindMap(text: mmd)) != nil
        report.append("- **Espresso Map.mmd** — \(reopens ? "✅ parses" : "❌ won't reopen") · \(childCount) flat children · \(mmPartial.outputTokens) tok · \(String(format: "%.1fs", mmElapsed))")
        report.append("")
        report.append("> Mind-map note: the in-app tool can only add **flat children under the root** — it cannot author nested hierarchy, and the model cannot emit Mindo's `.mmd` wire format directly. The map above is the realistic ceiling.")
        print("[TESTDRIVE] Espresso Map.mmd: reopens=\(reopens), \(childCount) children")

        try (report.joined(separator: "\n") + "\n")
            .write(to: outDir.appendingPathComponent("_testdrive-report.md"), atomically: true, encoding: .utf8)
        print("[TESTDRIVE] wrote docset + report to \(outDir.path)")
    }

    // <repo>/Tests/MindoMindMapTests/AgenticTestdrive.swift → <repo>
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Strip a single leading/trailing ``` fence. (Finding: the in-app tool does
    /// NOT do this — it inserts fenced text verbatim into the document.)
    static func stripCodeFence(_ s: String) -> String {
        var lines = s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, first.hasPrefix("```") else { return s }
        lines.removeFirst()
        if let last = lines.last, last.hasPrefix("```") { lines.removeLast() }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
