import Foundation
import MindoCore

/// Renders PlantUML source to SVG by spawning the `plantuml` CLI or `java -jar plantuml.jar`.
///
/// Discovery order:
///   1. `PLANTUML_JAR` env var pointing at a `.jar`
///   2. `plantuml` on `$PATH` (Homebrew installs `/opt/homebrew/bin/plantuml`)
///   3. `~/Library/Application Support/Mindo/plantuml.jar`
///   4. Common Homebrew install locations for the jar
///
/// When nothing is found, `render` returns a `.toolMissing` error whose `installHint`
/// is suitable for inline display in the preview pane.
public final class PlantUMLRenderer {
    public static let shared = PlantUMLRenderer()

    public enum Tool {
        case cli(URL)              // plantuml binary
        case jar(java: URL, jar: URL)
    }

    public enum RenderError: Error, LocalizedError {
        case toolMissing(installHint: String)
        case timeout
        case nonZeroExit(code: Int32, stderr: String)
        case empty

        public var errorDescription: String? {
            switch self {
            case .toolMissing(let hint): return hint
            case .timeout: return "PlantUML rendering timed out"
            case .nonZeroExit(let code, let stderr): return "plantuml exit \(code): \(stderr)"
            case .empty: return "PlantUML returned no output"
            }
        }
    }

    public init() {}

    /// Locate a usable PlantUML tool. Returns `nil` when nothing is installed.
    public func locate() -> Tool? {
        let fm = FileManager.default

        if let jarPath = ProcessInfo.processInfo.environment["PLANTUML_JAR"],
           fm.fileExists(atPath: jarPath),
           let java = locateJava() {
            return .jar(java: java, jar: URL(fileURLWithPath: jarPath))
        }

        let cliCandidates = [
            "/opt/homebrew/bin/plantuml",
            "/usr/local/bin/plantuml",
            "/usr/bin/plantuml",
        ]
        for path in cliCandidates where fm.isExecutableFile(atPath: path) {
            return .cli(URL(fileURLWithPath: path))
        }

        let userJar = applicationSupportDirectory.appendingPathComponent("plantuml.jar")
        if fm.fileExists(atPath: userJar.path), let java = locateJava() {
            return .jar(java: java, jar: userJar)
        }

        let jarCandidates = [
            "/opt/homebrew/Cellar/plantuml",
            "/usr/local/Cellar/plantuml",
        ]
        for cellar in jarCandidates {
            guard let versions = try? fm.contentsOfDirectory(atPath: cellar), let v = versions.first else { continue }
            let jarDir = "\(cellar)/\(v)/libexec"
            if let entries = try? fm.contentsOfDirectory(atPath: jarDir),
               let jar = entries.first(where: { $0.hasSuffix(".jar") }),
               let java = locateJava() {
                return .jar(java: java, jar: URL(fileURLWithPath: "\(jarDir)/\(jar)"))
            }
        }

        return nil
    }

    public var isAvailable: Bool { locate() != nil }

    /// User-facing install instructions for the preview pane when no tool is found.
    public var installHint: String {
        """
        PlantUML is not installed.

        To enable PlantUML rendering, install via Homebrew:
            brew install plantuml graphviz

        Or download plantuml.jar manually and place it at:
            \(applicationSupportDirectory.appendingPathComponent("plantuml.jar").path)

        After installing, re-open this file.
        """
    }

    /// Render the given PlantUML source synchronously and return the SVG bytes.
    /// Uses a 30s timeout. Throws `RenderError` on any failure.
    ///
    /// Sequence diagrams render **natively** (no Java) via the in-process SVG
    /// renderer; everything else falls through to the PlantUML CLI/jar. The
    /// native path needs no external tool, so it works even when Java is absent.
    public func renderSVG(source: String, isDark: Bool = false, timeout: TimeInterval = 30) throws -> Data {
        if let native = SequenceSVGRenderer.renderSequenceSVG(source: source, isDark: isDark),
           let data = native.data(using: .utf8) {
            return data
        }
        return try renderViaCLI(source: source, formatFlag: "-tsvg", timeout: timeout)
    }

    /// Render the diagram as monospaced ASCII art via PlantUML `-tatxt`
    /// (javamind's "Copy ASCII"). Always uses the CLI/jar — there's no native
    /// ASCII path. #216.
    public func renderASCII(source: String, timeout: TimeInterval = 30) throws -> String {
        let data = try renderViaCLI(source: source, formatFlag: "-tatxt", timeout: timeout)
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { throw RenderError.empty }
        return text
    }

    /// Shared PlantUML CLI/jar shell-out (`-pipe <formatFlag>`): feeds `source`
    /// on stdin and returns stdout. Used by both SVG and ASCII rendering.
    private func renderViaCLI(source: String, formatFlag: String, timeout: TimeInterval) throws -> Data {
        guard let tool = locate() else {
            throw RenderError.toolMissing(installHint: installHint)
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        switch tool {
        case .cli(let url):
            process.executableURL = url
            process.arguments = ["-pipe", formatFlag]
        case .jar(let java, let jar):
            process.executableURL = java
            process.arguments = ["-jar", jar.path, "-pipe", formatFlag]
        }

        // Forward a custom Graphviz path when the user pinned one in
        // Preferences. PlantUML respects GRAPHVIZ_DOT for sequence /
        // class / state diagrams. We carry the parent environment
        // forward so PATH + JAVA_HOME etc still work.
        if let dotPath = PrefKeys.string(PrefKeys.plantumlGraphvizPath) {
            var env = ProcessInfo.processInfo.environment
            env["GRAPHVIZ_DOT"] = dotPath
            process.environment = env
        }

        do { try process.run() }
        catch { throw RenderError.nonZeroExit(code: -1, stderr: error.localizedDescription) }

        // Feed source on a background queue so we don't deadlock on a large stdin.
        let inputData = source.data(using: .utf8) ?? Data()
        DispatchQueue.global().async {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: inputData)
            try? stdinPipe.fileHandleForWriting.close()
        }

        // Drain output streams while waiting.
        let group = DispatchGroup()
        var stdoutData = Data()
        var stderrData = Data()
        group.enter()
        DispatchQueue.global().async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let timedOut = group.wait(timeout: .now() + timeout) == .timedOut
        if timedOut {
            process.terminate()
            throw RenderError.timeout
        }
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = String(data: stderrData, encoding: .utf8) ?? ""
            throw RenderError.nonZeroExit(code: process.terminationStatus, stderr: err)
        }
        guard !stdoutData.isEmpty else { throw RenderError.empty }
        return stdoutData
    }

    // MARK: - Helpers

    private func locateJava() -> URL? {
        let fm = FileManager.default
        let candidates = [
            ProcessInfo.processInfo.environment["JAVA_HOME"].map { "\($0)/bin/java" },
            "/usr/bin/java",
            "/opt/homebrew/opt/openjdk/bin/java",
            "/opt/homebrew/bin/java",
            "/usr/local/bin/java",
        ].compactMap { $0 }
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        // Fall back to /usr/libexec/java_home output.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/libexec/java_home")
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        if (try? proc.run()) != nil {
            proc.waitUntilExit()
            if proc.terminationStatus == 0,
               let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) {
                let home = out.trimmingCharacters(in: .whitespacesAndNewlines)
                let java = "\(home)/bin/java"
                if fm.isExecutableFile(atPath: java) { return URL(fileURLWithPath: java) }
            }
        }
        return nil
    }

    private var applicationSupportDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Mindo", isDirectory: true)
    }
}
