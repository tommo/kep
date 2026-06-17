import SwiftUI

/// Provider / connection / model configuration, as Form `Section`s so it can be
/// embedded in either the Settings-window AI tab or the standalone sheet. Edits
/// persist to `LLMConfigStore.shared` immediately.
public struct AIProviderConfig: View {
    @State private var selectedProvider: GenAIProviderID = .openAI
    @State private var apiKey: String = ""
    @State private var endpoint: String = ""
    @State private var activeModel: String = ""

    public init() {}

    public var body: some View {
        Section("Provider") {
            Picker("Provider", selection: $selectedProvider) {
                ForEach(GenAIProviderID.allCases, id: \.self) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .onChange(of: selectedProvider) { _, _ in loadFromStore() }
        }

        Section("Connection") {
            SecureField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            if apiKey.isEmpty, let env = selectedProvider.apiKeyEnvVar {
                Text("Leave blank to use $\(env) from the environment.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Endpoint (leave blank for default)", text: $endpoint,
                      prompt: Text(selectedProvider.defaultEndpoint))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            Button("Save Connection") { saveConnection() }
                .buttonStyle(.borderedProminent)
        }

        Section("Active Model") {
            Picker("Model", selection: $activeModel) {
                ForEach(LLMConfigStore.shared.allModels(for: selectedProvider), id: \.name) { m in
                    Text(m.name).tag(m.name)
                }
            }
            .onChange(of: activeModel) { _, newModel in
                guard !newModel.isEmpty else { return }
                LLMConfigStore.shared.setActive(provider: selectedProvider, model: newModel)
            }
        }
        .onAppear(perform: loadFromStore)
    }

    private func loadFromStore() {
        let store = LLMConfigStore.shared
        // Show the active provider first if one is set.
        if let active = store.config.activeProviderID,
           let p = GenAIProviderID(rawValue: active), selectedProvider == .openAI, apiKey.isEmpty {
            selectedProvider = p
        }
        let meta = store.providerMeta(for: selectedProvider)
        apiKey = (store.config.providers[selectedProvider.rawValue]?.apiKey).flatMap { $0.isEmpty ? nil : $0 } ?? ""
        endpoint = (meta.endpoint == selectedProvider.defaultEndpoint) ? "" : meta.endpoint
        if store.config.activeProviderID == selectedProvider.rawValue, let model = store.config.activeModel {
            activeModel = model
        } else {
            activeModel = store.allModels(for: selectedProvider).first?.name ?? ""
        }
    }

    private func saveConnection() {
        let endpointToStore = endpoint.trimmingCharacters(in: .whitespaces).isEmpty
            ? selectedProvider.defaultEndpoint
            : endpoint
        LLMConfigStore.shared.setProviderMeta(
            ProviderMeta(apiKey: apiKey, endpoint: endpointToStore),
            for: selectedProvider
        )
    }
}

/// Standalone settings sheet (kept for the menu/gear paths). Wraps
/// `AIProviderConfig` with a title + Done button.
public struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("AI Settings").font(.title2).bold()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            Form { AIProviderConfig() }
                .formStyle(.grouped)
        }
        .frame(width: 500, height: 480)
    }
}
