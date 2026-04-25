import AppKit
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

    /// MARK: - Public undoable mutators
    ///
    /// These rebuild the element tree and notify `onChange`, mirroring the
    /// non-undoable internals already in `MindMapView`.

    public func undoableAddChild(to parent: Topic, text: String) -> Topic {
        let child = Topic(text: text)
        parent.append(child)
        registerUndo(
            name: "Add Topic",
            forward: { parent.append(child) },
            inverse: { parent.removeChild(child) }
        )
        rebuildElementsForUndo()
        notifyChangeForUndo()
        return child
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
        rebuildElementsForUndo()
        notifyChangeForUndo()
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
        rebuildElementsForUndo()
        notifyChangeForUndo()
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
        rebuildElementsForUndo()
        notifyChangeForUndo()
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
        rebuildElementsForUndo()
        notifyChangeForUndo()
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
