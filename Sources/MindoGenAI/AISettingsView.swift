import SwiftUI

/// Settings sheet for configuring LLM providers. Edits persist to
/// `LLMConfigStore.shared` immediately; the `Done` button just dismisses.
public struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider: GenAIProviderID = .openAI
    @State private var apiKey: String = ""
    @State private var endpoint: String = ""
    @State private var activeModel: String = ""

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

            Form {
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
                    TextField("Endpoint (leave blank for default)", text: $endpoint, prompt: Text(selectedProvider.defaultEndpoint))
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
                        LLMConfigStore.shared.setActive(provider: selectedProvider, model: newModel)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 500, height: 480)
        .onAppear { loadFromStore() }
    }

    private func loadFromStore() {
        let store = LLMConfigStore.shared
        let meta = store.providerMeta(for: selectedProvider)
        apiKey = meta.apiKey
        endpoint = (meta.endpoint == selectedProvider.defaultEndpoint) ? "" : meta.endpoint
        if let active = store.config.activeProviderID,
           active == selectedProvider.rawValue,
           let model = store.config.activeModel {
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

