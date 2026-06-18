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
    /// When true, plain Return sends and ⇧Return inserts a newline; otherwise
    /// Return inserts a newline and ⌘Return sends. Persisted.
    @AppStorage("ai.sendOnReturn") private var sendOnReturn = false

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
                Toggle("Send on Return (⇧↩ for newline)", isOn: $sendOnReturn)
                Divider()
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
                    if vm.isRunning {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small)
                            Text(vm.agentMode ? "Working…" : "Thinking…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("busy")
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
    /// Render a chat message as Markdown — bold/italic/code/links/lists/etc.
    /// Block syntax is interpreted but whitespace/newlines preserved so the
    /// reply's paragraph structure survives. Falls back to plain text.
    static func markdown(_ s: String) -> AttributedString {
        let opts = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible)
        return (try? AttributedString(markdown: s, options: opts)) ?? AttributedString(s)
    }

    private func bubble(_ turn: Conversation.Turn) -> some View {
        let isUser = turn.role == .user
        let rendered = Self.markdown(turn.content)
        return VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 0) {
                if isUser { Spacer(minLength: 16) }
                Text(rendered)
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
        // No send button — ⌘↩ sends (Return inserts a newline). The shortcut
        // lives on a hidden button so removing the visible control keeps it.
        ZStack(alignment: .topLeading) {
            if vm.draft.isEmpty {
                Text((vm.agentMode ? "Ask the assistant to do something… "
                                   : "Message the assistant… ") + sendHint)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $vm.draft)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 20, maxHeight: 110)
                .fixedSize(horizontal: false, vertical: true)
                .focused($inputFocused)
                .onKeyPress(phases: .down) { press in
                    // In send-on-Return mode, a plain Return sends (⇧Return makes
                    // a newline); otherwise let the editor handle it (⌘Return
                    // sends via the hidden shortcut button).
                    guard sendOnReturn, press.key == .return,
                          press.modifiers.isEmpty, vm.canSend else { return .ignored }
                    vm.setContext(contextProvider?())
                    vm.send()
                    return .handled
                }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 13).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color.secondary.opacity(0.28)))
        .padding(8)
        .background(sendShortcut)
    }

    private var sendHint: String { sendOnReturn ? "(↩ to send)" : "(⌘↩ to send)" }

    /// Invisible carrier for the ⌘↩ send shortcut.
    private var sendShortcut: some View {
        Button("") {
            guard vm.canSend else { return }
            vm.setContext(contextProvider?())
            vm.send()
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(!vm.canSend)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}
