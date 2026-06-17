import XCTest
import Foundation
@testable import MindoGenAI

final class LLMConfigEnvTests: XCTestCase {

    private func freshStore() -> LLMConfigStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mindo-llmcfg-test-\(ProcessInfo.processInfo.globallyUniqueString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return LLMConfigStore(directory: dir)   // empty config, no persisted keys
    }

    func testProviderMetaFallsBackToEnvKey() {
        setenv("DEEPSEEK_API_KEY", "sk-env-deepseek", 1)
        defer { unsetenv("DEEPSEEK_API_KEY") }
        let store = freshStore()
        XCTAssertEqual(store.providerMeta(for: .deepSeek).apiKey, "sk-env-deepseek")
        XCTAssertTrue(store.hasUsableKey(for: .deepSeek))
    }

    func testConfiguredKeyWinsOverEnv() {
        setenv("DEEPSEEK_API_KEY", "sk-env", 1)
        defer { unsetenv("DEEPSEEK_API_KEY") }
        let store = freshStore()
        store.setProviderMeta(ProviderMeta(apiKey: "sk-configured"), for: .deepSeek)
        XCTAssertEqual(store.providerMeta(for: .deepSeek).apiKey, "sk-configured")
    }

    func testActiveSelectionPrefersProviderWithKeyNotOllama() {
        // Clear any inherited provider keys so only DeepSeek has one.
        for v in ["OPENAI_API_KEY", "GEMINI_API_KEY", "DASHSCOPE_API_KEY",
                  "MOONSHOT_API_KEY", "ZHIPU_API_KEY", "HUGGINGFACE_API_KEY"] { unsetenv(v) }
        setenv("DEEPSEEK_API_KEY", "sk-env-deepseek", 1)
        defer { unsetenv("DEEPSEEK_API_KEY") }
        let store = freshStore()
        let sel = store.activeSelection()
        XCTAssertEqual(sel?.0, .deepSeek, "should auto-select the keyed provider, not keyless Ollama")
    }
}
