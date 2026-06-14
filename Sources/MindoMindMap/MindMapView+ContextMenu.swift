import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MindoModel

extension MindMapView {

    /// Build an NSMenu of Add/Edit/Remove actions for Note, Link, File extras
    /// plus an Image submenu for the `mmd.image` attribute, and a Delete
    /// Topic action for non-root topics. Called from `rightMouseDown`.
    func makeContextMenu(for element: MindMapElement) -> NSMenu {
        let menu = NSMenu()
        addExtraSection(menu, type: .note, target: element, label: "Note", placeholder: "Note text")
        addExtraSection(menu, type: .link, target: element, label: "Link", placeholder: "https://example.com")
        addExtraSection(menu, type: .file, target: element, label: "File", placeholder: "/path/to/file")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeContextItem(title: "Set Fill Color…", action: #selector(contextSetFillColor(_:)), payload: element))
        menu.addItem(makeContextItem(title: "Set Text Color…", action: #selector(contextSetTextColor(_:)), payload: element))
        menu.addItem(makeContextItem(title: "Set Border Color…", action: #selector(contextSetBorderColor(_:)), payload: element))
        let hasAnyColor = element.customFillColor != nil || element.customTextColor != nil || element.customBorderColor != nil
        if hasAnyColor {
            menu.addItem(makeContextItem(title: "Reset Colors", action: #selector(contextResetColors(_:)), payload: element))
        }
        menu.addItem(NSMenuItem.separator())
        let hasImage = element.topic.attribute(TopicAttribute.image) != nil
        menu.addItem(makeContextItem(
            title: hasImage ? "Replace Image…" : "Add Image…",
            action: #selector(contextSetImage(_:)),
            payload: element
        ))
        // Mindolph parity (AddImageChooseDialog): pull an image straight
        // from the pasteboard (e.g. macOS screenshot, copied browser
        // image). Hidden when the pasteboard has nothing usable so the
        // menu doesn't sprout a perma-disabled entry.
        if MindMapPasteHelper.imageBase64(from: NSPasteboard.general) != nil {
            menu.addItem(makeContextItem(
                title: hasImage ? "Replace Image from Clipboard" : "Add Image from Clipboard",
                action: #selector(contextSetImageFromClipboard(_:)),
                payload: element
            ))
        }
        if hasImage {
            menu.addItem(makeContextItem(title: "Remove Image", action: #selector(contextRemoveImage(_:)), payload: element))
        }
        menu.addItem(NSMenuItem.separator())
        let hasEmoticon = element.emoticonName != nil
        menu.addItem(makeContextItem(
            title: hasEmoticon ? "Change Icon…" : "Set Icon…",
            action: #selector(contextSetEmoticon(_:)),
            payload: element
        ))
        if hasEmoticon {
            menu.addItem(makeContextItem(title: "Remove Icon", action: #selector(contextRemoveEmoticon(_:)), payload: element))
        }
        menu.addItem(NSMenuItem.separator())
        // Clone (only meaningful for non-root topics — root has no parent slot
        // to insert a sibling into).
        if element.topic.parent != nil {
            menu.addItem(makeContextItem(title: "Duplicate Topic", action: #selector(contextDuplicateTopic(_:)), payload: element))
            if !element.topic.children.isEmpty {
                menu.addItem(makeContextItem(title: "Clone with Subtree", action: #selector(contextCloneTopicDeep(_:)), payload: element))
            }
        }
        // Convert multiline → subtree. Only show when the text actually
        // splits into 2+ non-empty lines so the menu entry isn't a no-op.
        if ConvertMultiline.split(element.topic.text).count >= 2 {
            menu.addItem(makeContextItem(title: "Convert to Subtree", action: #selector(contextConvertToSubtree(_:)), payload: element))
        }
        // Edit Text — shortcut for double-click / F2 inline-edit, parity with
        // Mindolph's RMB menu.
        menu.addItem(makeContextItem(title: "Edit Text", action: #selector(contextEditText(_:)), payload: element))
        // Per-subtree fold / unfold (separate from the global Fold All in
        // the View menu). Only meaningful when this topic has descendants.
        if !element.topic.children.isEmpty {
            menu.addItem(makeContextItem(title: "Fold Subtree", action: #selector(contextFoldSubtree(_:)), payload: element))
            menu.addItem(makeContextItem(title: "Unfold Subtree", action: #selector(contextUnfoldSubtree(_:)), payload: element))
        }
        // Export Branch As → submenu. Only meaningful when there's something
        // to export beyond the topic's own headline.
        let exportParent = NSMenuItem(title: "Export Branch As…", action: nil, keyEquivalent: "")
        let exportSub = NSMenu()
        for fmt in BranchExportFormat.allCases {
            exportSub.addItem(makeContextItem(
                title: fmt.menuTitle,
                action: #selector(contextExportBranch(_:)),
                payload: BranchExportPayload(element: element, format: fmt)
            ))
        }
        exportParent.submenu = exportSub
        menu.addItem(exportParent)

        // Text alignment submenu.
        let alignParent = NSMenuItem(title: "Text Alignment", action: nil, keyEquivalent: "")
        let alignSub = NSMenu()
        let current = TopicTextAlign.from(attribute: element.topic.attribute(TopicAttribute.textAlign))
        for option in [TopicTextAlign.left, .center, .right] {
            let title = option == .left ? "Left" : option == .center ? "Center" : "Right"
            let item = makeContextItem(title: title, action: #selector(contextSetTextAlign(_:)), payload: TextAlignPayload(element: element, alignment: option))
            item.state = current == option ? .on : .off
            alignSub.addItem(item)
        }
        alignParent.submenu = alignSub
        menu.addItem(alignParent)
        menu.addItem(NSMenuItem.separator())
        let deleteItem = makeContextItem(title: "Delete Topic", action: #selector(contextDeleteTopic(_:)), payload: element)
        deleteItem.isEnabled = element.topic.parent != nil
        menu.addItem(deleteItem)
        return menu
    }

    @objc func contextDuplicateTopic(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        if let clone = undoableCloneTopic(element.topic, deep: false),
           let cloneEl = self.element(forTopic: clone) {
            selectElement(cloneEl)
        }
    }

    @objc func contextCloneTopicDeep(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        if let clone = undoableCloneTopic(element.topic, deep: true),
           let cloneEl = self.element(forTopic: clone) {
            selectElement(cloneEl)
        }
    }

    @objc func contextConvertToSubtree(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        undoableConvertMultilineToChildren(element.topic)
    }

    @objc func contextEditText(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        selectElement(element)
        beginInlineEdit(on: element)
    }

    @objc func contextFoldSubtree(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        undoableSetSubtreeCollapsed(rootedAt: element.topic, collapsed: true)
    }

    @objc func contextUnfoldSubtree(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        undoableSetSubtreeCollapsed(rootedAt: element.topic, collapsed: false)
    }

    @objc func contextExportBranch(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? BranchExportPayload else { return }
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: payload.format.fileExtension) {
            panel.allowedContentTypes = [type]
        }
        let stem = (payload.element.topic.text.split(separator: "\n").first.map(String.init) ?? "branch")
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(stem.isEmpty ? "branch" : stem).\(payload.format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Build a temporary MindMap rooted at a deep clone of the source so
        // we don't mutate the live tree (clone() leaves parent/map nil).
        let branchMap = MindMap(root: payload.element.topic.clone(deep: true))
        let body: String
        switch payload.format {
        case .mindmap:  body = branchMap.write()
        case .orgMode:  body = OrgModeExporter.export(branchMap)
        case .freemind: body = FreemindExporter.export(branchMap)
        case .markdown: body = MindMapMarkdownExporter.export(branchMap)
        case .asciidoc: body = AsciiDocExporter.export(branchMap)
        case .mindmup:  body = MindmupExporter.export(branchMap)
        case .text:     body = PlainTextExporter.export(branchMap)
        }
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    @objc func contextSetTextAlign(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? TextAlignPayload else { return }
        // Center is the default — clear the attribute instead of writing
        // "center" so .mmd files stay clean for unaligned topics.
        let value: String? = payload.alignment == .center ? nil : payload.alignment.rawValue
        undoableSetAttribute(payload.element.topic, key: TopicAttribute.textAlign, value: value)
    }

    /// NSMenuItem with target=self + a stashed payload. Hand-rolled because
    /// NSMenuItem's init doesn't take either, and we need both on every
    /// context entry.
    private func makeContextItem(title: String, action: Selector, payload: Any) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = payload
        return item
    }

    @objc func contextSetImage(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        let base64 = data.base64EncodedString()
        undoableSetAttribute(element.topic, key: TopicAttribute.image, value: base64)
    }

    /// Pull a base64-encoded PNG from `NSPasteboard.general` (the same
    /// pipeline ⌘V uses for image paste) and stash it on the topic's
    /// `mmd.image` attribute. No-op when the pasteboard has nothing
    /// usable — the menu item is gated so we won't usually land here
    /// in that state, but the guard keeps the action robust.
    @objc func contextSetImageFromClipboard(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement,
              let base64 = MindMapPasteHelper.imageBase64(from: NSPasteboard.general) else { return }
        undoableSetAttribute(element.topic, key: TopicAttribute.image, value: base64)
    }

    @objc func contextRemoveImage(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        undoableSetAttribute(element.topic, key: TopicAttribute.image, value: nil)
    }

    @objc func contextSetFillColor(_ sender: NSMenuItem) {
        promptForColor(on: sender, attributeKey: TopicAttribute.fillColor, label: "Fill")
    }

    @objc func contextSetTextColor(_ sender: NSMenuItem) {
        promptForColor(on: sender, attributeKey: TopicAttribute.textColor, label: "Text")
    }

    @objc func contextSetBorderColor(_ sender: NSMenuItem) {
        promptForColor(on: sender, attributeKey: TopicAttribute.borderColor, label: "Border")
    }

    @objc func contextSetEmoticon(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        presentEmoticonPicker(for: element)
    }

    /// Show a visual icon-grid popover anchored to the topic, replacing the
    /// old free-text NSAlert. Picking a glyph (or Clear) writes the
    /// `mmd.emoticon` attribute and dismisses.
    private func presentEmoticonPicker(for element: MindMapElement) {
        let current = element.topic.attribute(TopicAttribute.emoticon)
        let popover = NSPopover()
        popover.behavior = .transient
        weak var weakPopover: NSPopover?
        let picker = EmoticonPickerView(current: current) { [weak self] picked in
            self?.undoableSetAttribute(element.topic, key: TopicAttribute.emoticon, value: picked)
            weakPopover?.close()
        }
        weakPopover = popover
        popover.contentViewController = NSHostingController(rootView: picker)
        // Anchor to the topic's rect; fall back to the whole view if it's
        // somehow off-screen so the popover always appears.
        let rect = element.frame.isEmpty ? bounds : element.frame
        popover.show(relativeTo: rect, of: self, preferredEdge: .maxY)
    }

    @objc func contextRemoveEmoticon(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        undoableSetAttribute(element.topic, key: TopicAttribute.emoticon, value: nil)
    }

    @objc func contextResetColors(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        undoableSetAttribute(element.topic, key: TopicAttribute.fillColor, value: nil)
        undoableSetAttribute(element.topic, key: TopicAttribute.textColor, value: nil)
        undoableSetAttribute(element.topic, key: TopicAttribute.borderColor, value: nil)
    }

    /// Pick a topic color with the native macOS color picker. A borderless
    /// `NSColorWell` accessory (click → system color panel) replaces the old
    /// type-a-hex-string text field — no more knowing `#RRGGBB`. The OK /
    /// Clear / Cancel alert frame keeps the edit a single, cancellable,
    /// undoable change. We still write the same hex form so round-trips with
    /// javamind stay lossless.
    private func promptForColor(on sender: NSMenuItem, attributeKey: String, label: String) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        let alert = NSAlert()
        alert.messageText = "\(label) Color"
        alert.informativeText = "Pick a color, or Clear to use the theme default."

        let well = NSColorWell(frame: NSRect(x: 0, y: 0, width: 64, height: 32))
        well.color = MindMapColorPicker.seedColor(
            currentAttribute: element.topic.attribute(attributeKey),
            fallback: .labelColor)
        alert.accessoryView = well
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        // Closing the alert leaves the shared color panel up otherwise.
        NSColorPanel.shared.close()
        switch MindMapColorPicker.result(for: response, chosen: well.color) {
        case .cancelled:
            break
        case .clear:
            undoableSetAttribute(element.topic, key: attributeKey, value: nil)
        case .pick(let color):
            undoableSetAttribute(element.topic, key: attributeKey, value: MindMapColor.write(color))
        }
    }

    private func addExtraSection(_ menu: NSMenu, type: ExtraType, target element: MindMapElement, label: String, placeholder: String) {
        let payload = ExtraMenuPayload(element: element, type: type, placeholder: placeholder)
        if let existing = element.topic.extra(type) {
            menu.addItem(makeContextItem(title: "Edit \(label)…", action: #selector(contextEditExtra(_:)), payload: payload))
            menu.addItem(makeContextItem(title: "Remove \(label)", action: #selector(contextRemoveExtra(_:)), payload: payload))
            // Note-specific encrypt / decrypt + import/export entries.
            if type == .note {
                if NoteEncryption.looksEncrypted(existing.value) {
                    menu.addItem(makeContextItem(title: "Decrypt Note…", action: #selector(contextDecryptNote(_:)), payload: payload))
                } else {
                    menu.addItem(makeContextItem(title: "Encrypt Note…", action: #selector(contextEncryptNote(_:)), payload: payload))
                    menu.addItem(makeContextItem(title: "Import Note from File…", action: #selector(contextImportNote(_:)), payload: payload))
                    menu.addItem(makeContextItem(title: "Export Note to File…", action: #selector(contextExportNote(_:)), payload: payload))
                }
            }
        } else {
            menu.addItem(makeContextItem(title: "Add \(label)…", action: #selector(contextEditExtra(_:)), payload: payload))
            // Allow Import even when no note exists yet — creates one from file.
            if type == .note {
                menu.addItem(makeContextItem(title: "Import Note from File…", action: #selector(contextImportNote(_:)), payload: payload))
            }
        }
    }

    @objc func contextImportNote(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ExtraMenuPayload else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .text, UTType(filenameExtension: "md") ?? .text]
        guard panel.runModal() == .OK, let url = panel.url,
              let body = try? String(contentsOf: url, encoding: .utf8) else { return }
        undoableSetExtra(payload.element.topic, .note, value: ExtraNote(text: body))
    }

    @objc func contextExportNote(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ExtraMenuPayload,
              let note = payload.element.topic.extra(.note) as? ExtraNote,
              !NoteEncryption.looksEncrypted(note.text) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let stem = payload.element.topic.text.split(separator: "\n").first.map(String.init) ?? "Note"
        let safeStem = stem.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeStem.isEmpty ? "Note" : safeStem).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? note.text.write(to: url, atomically: true, encoding: .utf8)
    }

    @objc func contextEncryptNote(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ExtraMenuPayload,
              let plain = (payload.element.topic.extra(.note) as? ExtraNote)?.text,
              !NoteEncryption.looksEncrypted(plain) else { return }
        let alert = NSAlert()
        alert.messageText = "Encrypt Note"
        alert.informativeText = "Choose a password and an optional hint. The note body becomes opaque ciphertext until decrypted."
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 60))
        stack.orientation = .vertical
        stack.spacing = 6
        let pwd = NSSecureTextField(string: "")
        pwd.placeholderString = "Password"
        let hint = NSTextField(string: "")
        hint.placeholderString = "Hint (shown when prompting later)"
        stack.addArrangedSubview(pwd)
        stack.addArrangedSubview(hint)
        pwd.frame.size.width = 320
        hint.frame.size.width = 320
        alert.accessoryView = stack
        alert.addButton(withTitle: "Encrypt")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              !pwd.stringValue.isEmpty else { return }
        let cipher = NoteEncryption.encrypt(plaintext: plain, password: pwd.stringValue)
        let trimmedHint = hint.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = ExtraNote(text: cipher, encrypted: true, hint: trimmedHint.isEmpty ? nil : trimmedHint)
        undoableSetExtra(payload.element.topic, .note, value: extra)
    }

    @objc func contextDecryptNote(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ExtraMenuPayload,
              let note = payload.element.topic.extra(.note) as? ExtraNote,
              NoteEncryption.looksEncrypted(note.text) else { return }
        let alert = NSAlert()
        alert.messageText = "Decrypt Note"
        if let hint = note.hint, !hint.isEmpty {
            alert.informativeText = "Hint: \(hint)"
        } else {
            alert.informativeText = "Enter the password used to encrypt this note."
        }
        let pwd = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        alert.accessoryView = pwd
        alert.addButton(withTitle: "Decrypt")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn,
              !pwd.stringValue.isEmpty else { return }
        guard let plain = NoteEncryption.decrypt(note.text, password: pwd.stringValue) else {
            let fail = NSAlert()
            fail.messageText = "Wrong password"
            fail.informativeText = "Couldn't decrypt the note with that password."
            fail.alertStyle = .warning
            fail.runModal()
            return
        }
        let extra = ExtraNote(text: plain, encrypted: false, hint: nil)
        undoableSetExtra(payload.element.topic, .note, value: extra)
    }

    @objc func contextEditExtra(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ExtraMenuPayload else { return }
        let current = payload.element.topic.extra(payload.type)?.value ?? ""
        guard let value = promptForExtraValue(
            title: "\(payload.type == .note ? "Note" : payload.type == .link ? "Link" : "File")",
            placeholder: payload.placeholder,
            initial: current
        ) else { return }
        let extra: any Extra
        switch payload.type {
        case .note: extra = ExtraNote(text: value)
        case .link: extra = ExtraLink(uri: value)
        case .file: extra = ExtraFile(uri: value)
        case .topic: extra = ExtraTopic(topicUID: value)
        case .unknown: return
        }
        undoableSetExtra(payload.element.topic, payload.type, value: extra)
    }

    @objc func contextRemoveExtra(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ExtraMenuPayload else { return }
        undoableSetExtra(payload.element.topic, payload.type, value: nil)
    }

    @objc func contextDeleteTopic(_ sender: NSMenuItem) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        undoableRemove(element.topic)
        if let parent = element.topic.parent { selectElement(self.element(forTopic: parent)) }
    }

    /// Show a modal NSAlert with a multi-line text view. Returns nil when the
    /// user cancels. Returns the literal value otherwise — empty strings are
    /// allowed (Note can be empty); type-specific validation is the caller's job.
    func promptForExtraValue(title: String, placeholder: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "Enter the value"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 360, height: 80))
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 80))
        textView.isRichText = false
        textView.string = initial
        textView.font = .systemFont(ofSize: 13)
        textView.isEditable = true
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        alert.accessoryView = scroll
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let result = alert.runModal()
        guard result == .alertFirstButtonReturn else { return nil }
        return textView.string
    }
}

/// Per-item context payload for the Add/Edit/Remove menu items. Internal so
/// the extension file's @objc selectors can read it via `representedObject`.
struct ExtraMenuPayload {
    let element: MindMapElement
    let type: ExtraType
    let placeholder: String
}

/// Payload for the Text Alignment submenu — bundles the element + the
/// chosen alignment so the @objc handler can dispatch in one step.
struct TextAlignPayload {
    let element: MindMapElement
    let alignment: TopicTextAlign
}

/// One of the formats a branch can be exported as. Lives outside
/// MindMapView so the per-format file extension + label are unit-testable.
public enum BranchExportFormat: String, CaseIterable {
    case mindmap, orgMode, freemind, markdown, asciidoc, mindmup, text

    public var fileExtension: String {
        switch self {
        case .mindmap:  return "mmd"
        case .orgMode:  return "org"
        case .freemind: return "mm"
        case .markdown: return "md"
        case .asciidoc: return "adoc"
        case .mindmup:  return "mup"
        case .text:     return "txt"
        }
    }

    public var menuTitle: String {
        switch self {
        case .mindmap:  return "Mindo .mmd"
        case .orgMode:  return "Org-Mode (.org)"
        case .freemind: return "FreeMind (.mm)"
        case .markdown: return "Markdown (.md)"
        case .asciidoc: return "AsciiDoc (.adoc)"
        case .mindmup:  return "Mindmup (.mup)"
        case .text:     return "Plain Text Outline (.txt)"
        }
    }
}

/// Payload for the Export Branch submenu — bundles the element + the
/// chosen format so one @objc handler can dispatch all four entries.
struct BranchExportPayload {
    let element: MindMapElement
    let format: BranchExportFormat
}
