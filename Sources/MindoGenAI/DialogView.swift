import SwiftUI

/// Persistent conversational panel — multi-turn chat with the AI about the
/// active document. The host supplies an optional context block (active doc /
/// selection / resolved links) and an `onInsert` closure to drop a reply into
/// the document. Beyond the one-shot `AIGeneratePane`.
public struct DialogView: View {
    @StateObject private var vm: ConversationViewModel
    /// Insert an assistant reply into the active document. Nil hides the action.
    private let onInsert: ((String) -> Void)?
    /// Re-read just before each send so the model sees current doc state.
    private let contextProvider: (() -> String?)?

    @FocusState private var inputFocused: Bool
    @Environment(\.openSettings) private var openSettings

    public init(systemPrompt: String = Conversation.defaultSystemPrompt,
                contextProvider: (() -> String?)? = nil,
                onInsert: ((String) -> Void)? = nil,
                agentReply: (([ChatMessage]) async throws -> String)? = nil) {
        _vm = StateObject(wrappedValue: ConversationViewModel(
            systemPrompt: systemPrompt, contextBlock: contextProvider?(), agentReply: agentReply))
        self.contextProvider = contextProvider
        self.onInsert = onInsert
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            composer
        }
        .frame(minWidth: 220, minHeight: 280)
        .onAppear {
            vm.refreshProviderLabel()   // pick up provider/model configured since init
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { inputFocused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right").foregroundStyle(.purple)
            Text(vm.providerLabel).font(.caption).foregroundStyle(.secondary)
            // Model selection — fills the header; persisted as the active model.
            if vm.availableModels.count > 1 {
                Picker("", selection: $vm.selectedModel) {
                    ForEach(vm.availableModels, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: 180)
                .disabled(vm.isRunning)
            } else if !vm.selectedModel.isEmpty {
                Text(vm.selectedModel).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if vm.hasAgent {
                Toggle(isOn: $vm.agentMode) { Image(systemName: "wrench.and.screwdriver") }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Agent mode — let the assistant use tools to edit the map / query the knowledge base")
                    .disabled(vm.isRunning)
            }
            Button {
                vm.clear()
            } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Clear conversation")
                .disabled(vm.conversation.turns.isEmpty)
            Button {
                openSettings()
            } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help("AI provider & model settings")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if vm.conversation.turns.isEmpty {
                        VStack(spacing: 10) {
                            if vm.selectedModel.isEmpty {
                                Text("No AI provider configured.")
                                    .font(.callout).foregroundStyle(.secondary)
                                Button("Configure AI provider…") { openSettings() }
                                    .buttonStyle(.borderedProminent)
                            } else {
                                Text("Ask about the document you're editing — mind maps, notes, PlantUML, CSV.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 24)
                    }
                    ForEach(vm.conversation.turns) { turn in
                        bubble(turn)
                            .id(turn.id)
                    }
                    if let err = vm.errorText {
                        Text(err).font(.caption).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
            }
            .onChange(of: vm.conversation.turns.last?.content) { _, _ in
                if let id = vm.conversation.turns.last?.id {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(_ turn: Conversation.Turn) -> some View {
        let isUser = turn.role == .user
        VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            HStack {
                if isUser { Spacer(minLength: 40) }
                Text(turn.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(isUser ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12)))
                if !isUser { Spacer(minLength: 40) }
            }
            if !isUser, let onInsert, !turn.content.isEmpty, !vm.isRunning {
                Button {
                    onInsert(turn.content)
                } label: { Label("Insert into document", systemImage: "text.insert").font(.caption) }
                    .buttonStyle(.borderless)
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $vm.draft)
                .font(.body)
                .frame(minHeight: 38, maxHeight: 110)
                .padding(4)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                .focused($inputFocused)
            if vm.isRunning {
                Button { vm.cancel() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                    .buttonStyle(.borderless).help("Stop")
            } else {
                Button {
                    vm.setContext(contextProvider?())
                    vm.send()
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(!vm.canSend)
                    .help("Send (⌘↩)")
            }
        }
        .padding(10)
    }
}
