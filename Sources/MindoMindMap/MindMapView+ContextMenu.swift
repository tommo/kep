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
        let deleteItem = makeContextItem(title: "Delete Topic", action: #selector(contextDeleteTopic(_:)), payload: element)
        deleteItem.isEnabled = element.topic.parent != nil
        menu.addItem(deleteItem)
        return menu
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

    private func addExtraSection(_ menu: NSMenu, type: ExtraType, target element: MindMapElement, label: String, placeholder: String) {
        let payload = ExtraMenuPayload(element: element, type: type, placeholder: placeholder)
        if element.topic.extra(type) != nil {
            menu.addItem(makeContextItem(title: "Edit \(label)…", action: #selector(contextEditExtra(_:)), payload: payload))
            menu.addItem(makeContextItem(title: "Remove \(label)", action: #selector(contextRemoveExtra(_:)), payload: payload))
        } else {
            menu.addItem(makeContextItem(title: "Add \(label)…", action: #selector(contextEditExtra(_:)), payload: payload))
        }
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
