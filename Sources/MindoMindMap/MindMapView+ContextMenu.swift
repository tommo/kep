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
        let imageItem = NSMenuItem(
            title: hasImage ? "Replace Image…" : "Add Image…",
            action: #selector(contextSetImage(_:)),
            keyEquivalent: ""
        )
        imageItem.target = self
        imageItem.representedObject = element
        menu.addItem(imageItem)
        if hasImage {
            let removeImage = NSMenuItem(title: "Remove Image", action: #selector(contextRemoveImage(_:)), keyEquivalent: "")
            removeImage.target = self
            removeImage.representedObject = element
            menu.addItem(removeImage)
        }
        menu.addItem(NSMenuItem.separator())
        let deleteItem = NSMenuItem(title: "Delete Topic", action: #selector(contextDeleteTopic(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = element
        deleteItem.isEnabled = element.topic.parent != nil
        menu.addItem(deleteItem)
        return menu
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
        let exists = element.topic.extra(type) != nil
        if exists {
            let editItem = NSMenuItem(title: "Edit \(label)…", action: #selector(contextEditExtra(_:)), keyEquivalent: "")
            editItem.target = self
            editItem.representedObject = ExtraMenuPayload(element: element, type: type, placeholder: placeholder)
            menu.addItem(editItem)

            let removeItem = NSMenuItem(title: "Remove \(label)", action: #selector(contextRemoveExtra(_:)), keyEquivalent: "")
            removeItem.target = self
            removeItem.representedObject = ExtraMenuPayload(element: element, type: type, placeholder: placeholder)
            menu.addItem(removeItem)
        } else {
            let addItem = NSMenuItem(title: "Add \(label)…", action: #selector(contextEditExtra(_:)), keyEquivalent: "")
            addItem.target = self
            addItem.representedObject = ExtraMenuPayload(element: element, type: type, placeholder: placeholder)
            menu.addItem(addItem)
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
