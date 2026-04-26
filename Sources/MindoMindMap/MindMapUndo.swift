import AppKit
import MindoCore
import MindoModel

/// Helpers that wrap `Topic` mutations in `NSUndoManager` registrations.
/// Each helper performs the mutation immediately and queues an inverse so
/// `⌘Z` rolls back to the prior state. Calls re-register the *forward*
/// operation on undo, so redo (`⌘⇧Z`) replays.
extension MindMapView {

    /// Register a mutation pair on the responder-chain undo manager. `forward`
    /// has already been called by the caller — we only enqueue the inverse.
    /// Always wraps the registration in a group so callers don't need to
    /// rely on NSUndoManager's "groupsByEvent" runloop coalescing.
    func registerUndo(name: String, forward: @escaping () -> Void, inverse: @escaping () -> Void) {
        guard let manager = self.undoManager else { return }
        let needsGroup = manager.groupingLevel == 0
        if needsGroup { manager.beginUndoGrouping() }
        manager.setActionName(name)
        manager.registerUndo(withTarget: self) { view in
            inverse()
            view.refreshAfterMutation()
            view.registerUndo(name: name, forward: inverse, inverse: forward)
        }
        if needsGroup { manager.endUndoGrouping() }
    }

    func refreshAfterMutation() {
        rebuildElementsForUndo()
    }

    /// Element-rebuild + onChange — every public mutator ends with this pair.
    func refreshAndNotify() {
        rebuildElementsForUndo()
        notifyChangeForUndo()
    }

    /// MARK: - Public undoable mutators
    ///
    /// These rebuild the element tree and notify `onChange`, mirroring the
    /// non-undoable internals already in `MindMapView`.

    public func undoableAddChild(to parent: Topic, text: String) -> Topic {
        let child = Topic(text: text)
        // Pref-gated: cascade the parent's fill color to the new child so
        // colored category branches stay visually consistent. Off by
        // default (matches Mindolph's `PREF_KEY_MMD_COPY_COLOR_INFO_TO_NEW_CHILD`).
        if PrefKeys.bool(PrefKeys.mindmapInheritFillColor, fallback: false),
           let inherited = parent.attribute(TopicAttribute.fillColor) {
            child.setAttribute(TopicAttribute.fillColor, inherited)
        }
        parent.append(child)
        registerUndo(
            name: "Add Topic",
            forward: { parent.append(child) },
            inverse: { parent.removeChild(child) }
        )
        refreshAndNotify()
        return child
    }

    /// Split a topic whose text spans multiple lines into one parent (keeps
    /// the first non-empty line) plus N children (one per remaining
    /// non-empty line). No-op when the text contains fewer than 2 non-empty
    /// lines. Single undoable step. Existing children are preserved — new
    /// children are appended after them.
    public func undoableConvertMultilineToChildren(_ topic: Topic) {
        let lines = ConvertMultiline.split(topic.text)
        guard lines.count >= 2 else { return }
        let oldText = topic.text
        let newText = lines[0]
        let newChildTexts = Array(lines.dropFirst())

        let newChildren: [Topic] = newChildTexts.map { Topic(text: $0) }
        topic.text = newText
        for child in newChildren { topic.append(child) }

        registerUndo(
            name: "Convert to Subtree",
            forward: {
                topic.text = newText
                for child in newChildren {
                    if !topic.children.contains(where: { $0 === child }) {
                        topic.append(child)
                    }
                }
            },
            inverse: {
                topic.text = oldText
                for child in newChildren { topic.removeChild(child) }
            }
        )
        refreshAndNotify()
    }

    /// Clone `source` (optionally with its full subtree) and insert the
    /// clone as the next sibling of `source`. Single undoable step. The
    /// returned topic is the newly-inserted clone.
    @discardableResult
    public func undoableCloneTopic(_ source: Topic, deep: Bool) -> Topic? {
        guard let parent = source.parent else { return nil }  // can't clone the root
        let clone = source.clone(deep: deep)
        parent.append(clone)
        let sourceIdx = parent.children.firstIndex(where: { $0 === source }) ?? parent.children.endIndex
        parent.move(child: clone, to: sourceIdx + 1)
        registerUndo(
            name: deep ? "Clone Topic with Subtree" : "Clone Topic",
            forward: {
                parent.append(clone)
                parent.move(child: clone, to: sourceIdx + 1)
            },
            inverse: { parent.removeChild(clone) }
        )
        refreshAndNotify()
        return clone
    }

    public func undoableRemove(_ topic: Topic) {
        guard let parent = topic.parent else { return }
        let originalIndex = parent.children.firstIndex(where: { $0 === topic }) ?? parent.children.endIndex
        parent.removeChild(topic)
        registerUndo(
            name: "Delete Topic",
            forward: { parent.removeChild(topic) },
            inverse: { parent.move(child: topic, to: originalIndex); /* re-add if missing */
                if !parent.children.contains(where: { $0 === topic }) {
                    parent.append(topic)
                    parent.move(child: topic, to: originalIndex)
                }
            }
        )
        refreshAndNotify()
    }

    public func undoableSetText(_ topic: Topic, to newText: String) {
        let oldText = topic.text
        guard oldText != newText else { return }
        topic.text = newText
        registerUndo(
            name: "Edit Topic",
            forward: { topic.text = newText },
            inverse: { topic.text = oldText }
        )
        refreshAndNotify()
    }

    public func undoableSetAttribute(_ topic: Topic, key: String, value: String?) {
        let oldValue = topic.attribute(key)
        guard oldValue != value else { return }
        topic.setAttribute(key, value)
        registerUndo(
            name: value == nil ? "Clear \(key)" : "Set \(key)",
            forward: { topic.setAttribute(key, value) },
            inverse: { topic.setAttribute(key, oldValue) }
        )
        refreshAndNotify()
    }

    /// Bulk set/clear of the `collapsed` attribute on every topic that has
    /// children — backs Fold All / Unfold All. Captures every prior value so
    /// undo restores the exact prior fold state. No-op if nothing changes.
    public func undoableSetAllCollapsed(_ collapsed: Bool) {
        guard let root = mindMap?.root else { return }
        applyCollapse(rootedAt: root, collapsed: collapsed,
                      undoName: collapsed ? "Fold All" : "Unfold All")
    }

    /// Recursive fold/unfold for one subtree (root included). Same single-
    /// undo-step semantics as `undoableSetAllCollapsed`. Used by the
    /// per-topic context-menu Fold/Unfold Subtree commands.
    public func undoableSetSubtreeCollapsed(rootedAt topic: Topic, collapsed: Bool) {
        applyCollapse(rootedAt: topic, collapsed: collapsed,
                      undoName: collapsed ? "Fold Subtree" : "Unfold Subtree")
    }

    private func applyCollapse(rootedAt root: Topic, collapsed: Bool, undoName: String) {
        let value: String? = collapsed ? "true" : nil
        var changes: [(Topic, String?)] = []
        var stack: [Topic] = [root]
        while let t = stack.popLast() {
            if !t.children.isEmpty {
                let old = t.attribute(TopicAttribute.collapsed)
                if old != value { changes.append((t, old)) }
            }
            stack.append(contentsOf: t.children)
        }
        guard !changes.isEmpty else { return }
        for (topic, _) in changes { topic.setAttribute(TopicAttribute.collapsed, value) }
        registerUndo(
            name: undoName,
            forward: { for (topic, _) in changes { topic.setAttribute(TopicAttribute.collapsed, value) } },
            inverse: { for (topic, old) in changes { topic.setAttribute(TopicAttribute.collapsed, old) } }
        )
        refreshAndNotify()
    }

    /// Set or clear an extra on a topic. `nil` removes the extra. Captures
    /// the old extra (if any) for undo restoration; mirrors the per-attribute
    /// pattern but for the Extras EnumMap.
    public func undoableSetExtra(_ topic: Topic, _ type: ExtraType, value: (any Extra)?) {
        let oldExtra = topic.extra(type)
        if let new = value {
            topic.setExtra(new)
        } else {
            topic.removeExtra(type)
        }
        registerUndo(
            name: value == nil ? "Remove \(type.rawName)" : "Set \(type.rawName)",
            forward: {
                if let new = value { topic.setExtra(new) }
                else { topic.removeExtra(type) }
            },
            inverse: {
                if let old = oldExtra { topic.setExtra(old) }
                else { topic.removeExtra(type) }
            }
        )
        refreshAndNotify()
    }

    /// Move `topic` to be the `index`th child of `newParent`. Pure undoable
    /// reparent; covers drag-to-reparent gestures.
    public func undoableReparent(_ topic: Topic, to newParent: Topic, at index: Int) {
        guard let oldParent = topic.parent else { return }
        let oldIndex = oldParent.children.firstIndex(where: { $0 === topic }) ?? oldParent.children.endIndex
        oldParent.removeChild(topic)
        newParent.append(topic)
        newParent.move(child: topic, to: index)
        registerUndo(
            name: "Move Topic",
            forward: {
                oldParent.removeChild(topic)
                newParent.append(topic)
                newParent.move(child: topic, to: index)
            },
            inverse: {
                newParent.removeChild(topic)
                oldParent.append(topic)
                oldParent.move(child: topic, to: oldIndex)
            }
        )
        refreshAndNotify()
    }
}

// MARK: - Internal hooks (private to module)

extension MindMapView {
    /// Re-build elements + redraw. Re-exported with a distinct name so the
    /// extension above can call it without bumping into `private` access.
    func rebuildElementsForUndo() {
        rebuildElementsPublic()
    }

    func notifyChangeForUndo() {
        if let map = mindMap { onChange?(map) }
    }
}
