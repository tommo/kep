import AppKit
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
        let alert = NSAlert()
        alert.messageText = "Topic Icon"
        alert.informativeText = "Enter an icon name (e.g. star, bell, warning, idea). Leave blank to clear."
        let field = NSTextField(string: element.topic.attribute(TopicAttribute.emoticon) ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        field.placeholderString = "star, bell, warning…"
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let raw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        undoableSetAttribute(element.topic, key: TopicAttribute.emoticon, value: raw.isEmpty ? nil : raw)
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

    /// Prompt for a hex color via a small alert with a single text field.
    /// Mirrors Mindolph's color dialog at the input-format level — we accept
    /// the same `#RRGGBB` strings that javamind writes.
    private func promptForColor(on sender: NSMenuItem, attributeKey: String, label: String) {
        guard let element = sender.representedObject as? MindMapElement else { return }
        let alert = NSAlert()
        alert.messageText = "\(label) Color"
        alert.informativeText = "Enter a hex color (e.g. #4A90E2). Leave blank to clear."
        let field = NSTextField(string: element.topic.attribute(attributeKey) ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        field.placeholderString = "#RRGGBB"
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let raw = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty {
            undoableSetAttribute(element.topic, key: attributeKey, value: nil)
        } else if let parsed = MindMapColor.parse(raw) {
            undoableSetAttribute(element.topic, key: attributeKey, value: MindMapColor.write(parsed))
        }
    }

    private func addExtraSection(_ menu: NSMenu, type: ExtraType, target element: MindMapElement, label: String, placeholder: String) {
        let payload = ExtraMenuPayload(element: element, type: type, placeholder: placeholder)
        if let existing = element.topic.extra(type) {
            menu.addItem(makeContextItem(title: "Edit \(label)…", action: #selector(contextEditExtra(_:)), payload: payload))
            menu.addItem(makeContextItem(title: "Remove \(label)", action: #selector(contextRemoveExtra(_:)), payload: payload))
            // Note-specific encrypt / decrypt entries.
            if type == .note {
                if NoteEncryption.looksEncrypted(existing.value) {
                    menu.addItem(makeContextItem(title: "Decrypt Note…", action: #selector(contextDecryptNote(_:)), payload: payload))
                } else {
                    menu.addItem(makeContextItem(title: "Encrypt Note…", action: #selector(contextEncryptNote(_:)), payload: payload))
                }
            }
        } else {
            menu.addItem(makeContextItem(title: "Add \(label)…", action: #selector(contextEditExtra(_:)), payload: payload))
        }
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
