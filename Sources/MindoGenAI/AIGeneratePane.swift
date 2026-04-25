import SwiftUI
import Combine

/// Modal sheet that lets the user enter a prompt, watch the response stream in,
/// and insert it into the calling editor. The host passes a closure that knows
/// how to apply accepted text to the document.
public struct AIGeneratePane: View {
    public enum InsertionMode: String, CaseIterable, Hashable, Sendable {
        case append    = "Append"
        case replace   = "Replace selection"
        case childTopic = "As child topic"
    }

    public struct Context: Sendable {
        public var selectedText: String
        public var supportedModes: [InsertionMode]
        public var defaultPrompt: String
        public init(selectedText: String = "", supportedModes: [InsertionMode] = [.append, .replace], defaultPrompt: String = "") {
            self.selectedText = selectedText
            self.supportedModes = supportedModes
            self.defaultPrompt = defaultPrompt
        }
    }

    @Environment(\.dismiss) private var dismiss

    public let title: String
    public let context: Context
    public let onAccept: (String, InsertionMode) -> Void

    @State private var prompt: String
    @State private var insertionMode: InsertionMode
    @State private var output: String = ""
    @State private var isRunning: Bool = false
    @State private var errorMessage: String?
    @State private var providerLabel: String = ""
    @State private var subscriptions: Set<AnyCancellable> = []

    public init(
        title: String = "AI Generate",
        context: Context,
        onAccept: @escaping (String, InsertionMode) -> Void
    ) {
        self.title = title
        self.context = context
        self.onAccept = onAccept
        _prompt = State(initialValue: context.defaultPrompt)
        _insertionMode = State(initialValue: context.supportedModes.first ?? .append)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            promptSection
            Divider()
            outputSection
            Divider()
            footer
        }
        .frame(width: 600, height: 540)
        .onAppear { refreshActiveProviderLabel() }
        .onDisappear { cancel() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            Text(title).font(.title3).bold()
            Spacer()
            Text(providerLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Close") { cancel(); dismiss() }
        }
        .padding()
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Prompt").font(.headline)
                Spacer()
                if context.supportedModes.count > 1 {
                    Picker("", selection: $insertionMode) {
                        ForEach(context.supportedModes, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }
            }
            TextEditor(text: $prompt)
                .font(.body)
                .frame(minHeight: 80)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3)))
            if !context.selectedText.isEmpty {
                Text("Context (selected): \(context.selectedText.prefix(160))…")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Result").font(.headline)
                if isRunning {
                    ProgressView().controlSize(.small).padding(.leading, 6)
                }
                Spacer()
                if let err = errorMessage {
                    Text(err).foregroundStyle(.red).font(.caption).lineLimit(1)
                }
            }
            ScrollView {
                Text(output.isEmpty ? "—" : output)
                    .font(.system(.body, design: .default))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.06)))
        }
        .padding()
    }

    private var footer: some View {
        HStack {
            Button("Generate", systemImage: "play.fill") { startGenerate() }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(isRunning || prompt.isEmpty)
            if isRunning {
                Button("Stop") { cancel() }
            }
            Spacer()
            Button("Discard") { dismiss() }
            Button("Insert") {
                onAccept(output, insertionMode)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(output.isEmpty || isRunning)
        }
        .padding()
    }

    // MARK: - Actions

    private func refreshActiveProviderLabel() {
        if let (provider, model) = LLMConfigStore.shared.activeSelection() {
            providerLabel = "\(provider.displayName) · \(model)"
        } else {
            providerLabel = "No provider configured"
        }
    }

    private func startGenerate() {
        guard let (provider, model) = LLMConfigStore.shared.activeSelection() else {
            errorMessage = "Configure a provider in Settings first."
            return
        }
        let modelMeta = LLMConfigStore.shared.modelMeta(for: provider, name: model)
        let combined = context.selectedText.isEmpty
            ? prompt
            : "\(prompt)\n\nContext:\n\(context.selectedText)"
        let input = LLMInput(
            providerID: provider.rawValue,
            model: modelMeta.name,
            text: combined,
            maxTokens: modelMeta.maxTokens,
            isStreaming: true
        )

        output = ""
        errorMessage = nil
        isRunning = true
        subscriptions.removeAll()
        let service = LLMService.shared
        service.partials
            .receive(on: RunLoop.main)
            .sink { partial in
                if !partial.text.isEmpty { output.append(partial.text) }
                if partial.isStop { isRunning = false }
            }
            .store(in: &subscriptions)
        service.errors
            .receive(on: RunLoop.main)
            .sink { err in
                errorMessage = err.errorDescription
                isRunning = false
            }
            .store(in: &subscriptions)
        service.stream(input: input)
    }

    private func cancel() {
        LLMService.shared.cancel()
        isRunning = false
        subscriptions.removeAll()
    }
}
