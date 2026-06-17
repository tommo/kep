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
        HStack(spacing: 6) {
            // Model — the one thing users must see. Picker (full name) when there
            // are choices, else plain text. Provider is implied by the model name.
            if vm.availableModels.count > 1 {
                Picker("", selection: $vm.selectedModel) {
                    ForEach(vm.availableModels, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(vm.isRunning)
            } else {
                Text(vm.selectedModel.isEmpty ? vm.providerLabel : vm.selectedModel)
                    .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if vm.hasAgent {
                Toggle(isOn: $vm.agentMode) { Image(systemName: "wrench.and.screwdriver") }
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .help("Agent mode — let the assistant use tools to edit the map / query the knowledge base")
                    .disabled(vm.isRunning)
            }
            // Secondary actions collapse into one menu so the narrow panel keeps
            // its width for the model name.
            Menu {
                Button("Clear conversation") { vm.clear() }
                    .disabled(vm.conversation.turns.isEmpty)
                Button("AI Settings…") { openSettings() }
            } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .controlSize(.small)
                .fixedSize()
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
            HStack(spacing: 0) {
                if isUser { Spacer(minLength: 16) }
                Text(turn.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(isUser ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12)))
                if !isUser { Spacer(minLength: 16) }
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
        // Input grows with its content (1 line → a few), capped; the send button
        // sits beside it as a distinct circular control.
        HStack(alignment: .bottom, spacing: 8) {
            ZStack(alignment: .topLeading) {
                if vm.draft.isEmpty {
                    Text(vm.agentMode ? "Ask the assistant to do something…" : "Message the assistant…")
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 2)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $vm.draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 20, maxHeight: 96)
                    .fixedSize(horizontal: false, vertical: true)   // size to content, capped by maxHeight
                    .focused($inputFocused)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 13).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.secondary.opacity(0.28)))

            sendControl
        }
        .padding(8)
    }

    @ViewBuilder private var sendControl: some View {
        Button {
            if vm.isRunning { vm.cancel() }
            else { vm.setContext(contextProvider?()); vm.send() }
        } label: {
            Image(systemName: vm.isRunning ? "stop.fill" : "arrow.up")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(
                    vm.isRunning ? Color.secondary
                    : (vm.canSend ? Color.accentColor : Color.secondary.opacity(0.4))))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(!vm.isRunning && !vm.canSend)
        .help(vm.isRunning ? "Stop" : "Send (⌘↩)")
    }
}
