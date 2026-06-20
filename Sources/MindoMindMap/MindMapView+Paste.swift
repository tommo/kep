import AppKit
import MindoBase
import MindoCore
import MindoModel

extension MindMapView {

    /// The topics targeted by a copy/cut/delete: every selected topic with
    /// descendants pruned, in canvas (traversal) order. Falls back to the
    /// primary `selectedElement` when the multi-selection set is empty (e.g.
    /// a fresh single click that didn't populate `selectedTopics`).
    func selectionTopics() -> [Topic] {
        var topics: [Topic] = []
        if !selectedTopics.isEmpty, let root = rootElement {
            root.traverse { el in
                if selectedTopics.contains(ObjectIdentifier(el.topic)) { topics.append(el.topic) }
            }
        }
        if topics.isEmpty, let primary = selectedElement?.topic {
            topics = [primary]
        }
        return MindMapSelection.topLevel(topics)
    }

    /// ⌘C — serialize EVERY selected topic's subtree (descendants pruned) to
    /// JSON and put it on the pasteboard as a forest. Falls through silently
    /// when nothing is selected. (The bug this fixes: copy only ever took the
    /// primary topic, dropping the rest of a multi-selection.)
    @objc public func copy(_ sender: Any?) {
        let topics = selectionTopics()
        guard !topics.isEmpty,
              let data = try? TopicSubtreeCodec.encodeForest(topics.map { $0.clone(deep: true) }) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: NSPasteboard.PasteboardType(TopicSubtreeCodec.pasteboardType))
        // Mirror the visible labels as newline-joined plain text so paste
        // into a markdown editor / external app gets something useful.
        pb.setString(topics.map(\.text).joined(separator: "\n"), forType: .string)
    }

    /// ⌘X — copy then delete every selected (non-root) topic in ONE undo
    /// group, so a multi-cut is a single ⌘Z.
    @objc public func cut(_ sender: Any?) {
        let topics = selectionTopics().filter { $0.parent != nil }   // can't cut root
        guard !topics.isEmpty else { return }
        copy(sender)
        groupedUndo(name: topics.count > 1 ? "Cut Topics" : "Cut Topic") {
            for topic in topics { undoableRemove(topic) }
        }
    }

    /// Run `body`'s undoable mutations inside a single undo group so a
    /// batch (multi-cut, multi-paste) collapses to one ⌘Z. `registerUndo`
    /// only opens its own group when `groupingLevel == 0`, so wrapping here
    /// makes the inner calls share this group.
    func groupedUndo(name: String, _ body: () -> Void) {
        guard let manager = undoManager else { body(); return }
        manager.beginUndoGrouping()
        manager.setActionName(name)
        body()
        manager.endUndoGrouping()
    }

    /// Standard `paste(_:)` responder action — fires on ⌘V when the canvas
    /// is first responder. Priority order:
    ///  1. mindo topic-subtree → reparent the decoded subtree under the
    ///     selected topic (single undoable step).
    ///  2. image → embed as base64 PNG into `mmd.image`.
    /// NSView itself doesn't implement `paste(_:)` — informal action via
    /// `NSStandardKeyBindingResponding`, so no `override`.
    @objc public func paste(_ sender: Any?) {
        guard let topic = selectedElement?.topic else { return }
        let pb = NSPasteboard.general
        if let data = pb.data(forType: NSPasteboard.PasteboardType(TopicSubtreeCodec.pasteboardType)),
           let subtrees = try? TopicSubtreeCodec.decodeForest(data), !subtrees.isEmpty {
            // Graft every copied subtree under the target in one undo group.
            // undoableInsert (not reparent) so a single ⌘Z removes them.
            groupedUndo(name: subtrees.count > 1 ? "Paste Topics" : "Paste Topic") {
                for subtree in subtrees {
                    undoableInsert(subtree, into: topic, at: topic.children.count)
                }
            }
            return
        }
        if let base64 = MindMapPasteHelper.imageBase64(from: pb) {
            undoableSetAttribute(topic, key: TopicAttribute.image, value: base64)
            return
        }
        // Mindolph parity (ckbSmartTextPaste): plain-text paste parses
        // the clipboard as an indented outline. Tried last so the
        // mindo-native subtree + image branches still win when both
        // shapes are on the pasteboard.
        if PrefKeys.bool(PrefKeys.mindmapSmartTextPaste, fallback: true),
           let text = pb.string(forType: .string),
           let subtree = MindMapPasteHelper.smartTextSubtree(text) {
            undoableInsert(subtree, into: topic, at: topic.children.count)
            return
        }
    }

    /// Enable the system Edit > Copy / Cut / Paste menu items based on
    /// what's actually possible right now. Without this, the menu would
    /// stay perma-grey because NSView has no built-in actions.
    @objc public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return true }
        switch action {
        case #selector(copy(_:)):
            return selectedElement != nil
        case #selector(cut(_:)):
            return selectedElement?.topic.parent != nil  // can't cut root
        case #selector(paste(_:)):
            guard selectedElement != nil else { return false }
            let pb = NSPasteboard.general
            if pb.data(forType: NSPasteboard.PasteboardType(TopicSubtreeCodec.pasteboardType)) != nil { return true }
            if MindMapPasteHelper.imageBase64(from: pb) != nil { return true }
            // Smart text paste — only enable Paste when the toggle is on
            // AND there's actual text on the pasteboard; keeps the menu
            // honest when the pref is flipped off.
            if PrefKeys.bool(PrefKeys.mindmapSmartTextPaste, fallback: true),
               let text = pb.string(forType: .string),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
            return false
        default:
            return true
        }
    }
}

/// Pure-logic pasteboard reader for the canvas paste path. Lives outside
/// the view so the "what's worth pasting" logic is unit-testable without
/// instantiating an NSView. Currently handles image-bearing pasteboards;
/// future work (#93 topic subtree) plugs in here too.
public enum MindMapPasteHelper {
    /// Extract a base64-encoded PNG from the pasteboard if it carries any
    /// representable image. Returns nil when the pasteboard has no image.
    /// PNG is the format `mmd.image` already round-trips through
    /// (FreeMind imports + context-menu Set Image both store PNG base64).
    /// Parse `text` as an indented outline (via TextOutlineImporter)
    /// and return the resulting root topic — ready to graft as a new
    /// child of the paste target. Returns nil for whitespace-only or
    /// empty input. Single-line input still returns a one-topic tree.
    /// Pure-logic: no NSPasteboard / NSView dependencies so the
    /// behavior is unit-testable.
    public static func smartTextSubtree(_ text: String) -> Topic? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let map = try? TextOutlineImporter.parse(text), let root = map.root else { return nil }
        // Detach from the temporary map so the caller can graft cleanly.
        // clone(deep:) produces an unowned subtree (parent / map nil) —
        // matches what undoableReparent expects for new children.
        return root.clone(deep: true)
    }

    public static func imageBase64(from pasteboard: NSPasteboard) -> String? {
        PasteboardImage.base64(from: pasteboard)
    }
}
