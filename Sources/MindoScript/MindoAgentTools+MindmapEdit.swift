import Foundation
import MindoModel

// G3 — Mindmap structural edits. Implemented by the agent-tools sprint.
extension MindoAgentTools {
    static let mindmapEditDescriptors: [(name: String, description: String, parametersJSON: String)] = [
        ("add_sibling_topic", "Add a sibling next to a reference topic (targeted by `path` or `query` substring). The new topic is placed right after the reference, or before it when `before` is true. Cannot target the root (it has no siblings).",
         #"{"type":"object","properties":{"query":{"type":"string"},"path":{"type":"string"},"text":{"type":"string"},"before":{"type":"boolean"}},"required":["text"]}"#),
        ("move_topic", "Move a topic (targeted by `path` or `query`) under a new parent. Identify the new parent by `to_parent_path` (outline path) or `to_parent` (substring). Optional `index` positions it among the new parent's children; omit to append. Fails on cycles (moving under self/descendant).",
         #"{"type":"object","properties":{"query":{"type":"string"},"path":{"type":"string"},"to_parent":{"type":"string"},"to_parent_path":{"type":"string"},"index":{"type":"integer"}},"required":[]}"#),
        ("build_subtree", "Build a nested tree of topics from an indented `outline` (2 spaces or one tab per level) under a parent (targeted by `parent_path` or `parent` substring; defaults to the root). Blank lines are skipped.",
         #"{"type":"object","properties":{"parent":{"type":"string"},"parent_path":{"type":"string"},"outline":{"type":"string"}},"required":["outline"]}"#),
        ("sort_children", "Sort a topic's immediate children alphabetically (targeted by `path` or `query`). `descending` true sorts Z→A.",
         #"{"type":"object","properties":{"query":{"type":"string"},"path":{"type":"string"},"descending":{"type":"boolean"}}}"#),
    ]

    func handleMindmapEdit(_ name: String, _ a: ToolArgs) -> String? {
        switch name {
        case "add_sibling_topic":
            guard let text = a.str("text") else { return "error: missing 'text'" }
            guard let ref = resolveTopic(a) else { return "error: no topic matches the given path/query" }
            guard let parent = ref.parent else { return "error: can't add a sibling to the root topic" }
            let sibling = parent.addChild(text: text)
            guard let refIdx = parent.children.firstIndex(where: { $0 === ref }) else {
                // Should not happen, but never crash.
                effects.mapMutated = true
                return "added sibling \"\(text)\" at [\(sibling.outlinePath)]"
            }
            let target = a.bool("before") == true ? refIdx : refIdx + 1
            parent.move(child: sibling, to: target)
            effects.mapMutated = true
            return "added sibling \"\(text)\" at [\(sibling.outlinePath)]"

        case "move_topic":
            guard let topic = resolveTopic(a) else { return "error: no topic matches the given path/query" }
            guard let oldParent = topic.parent else { return "error: can't move the root topic" }
            let newParent: Topic
            if let pp = a.str("to_parent_path") {
                guard let p = map.topic(atOutlinePath: pp) else { return "error: no parent matches 'to_parent_path'" }
                newParent = p
            } else if let pq = a.str("to_parent") {
                guard let p = firstTopic(matching: pq) else { return "error: no parent matches 'to_parent'" }
                newParent = p
            } else {
                return "error: missing 'to_parent' or 'to_parent_path'"
            }
            if newParent === topic { return "error: can't move a topic under itself" }
            if newParent.isDescendant(of: topic) { return "error: can't move a topic under its own descendant" }
            oldParent.removeChild(topic)
            if let idx = a.int("index") {
                newParent.insert(topic, at: idx)
            } else {
                newParent.append(topic)
            }
            effects.mapMutated = true
            return "moved \"\(topic.text)\" to [\(topic.outlinePath)]"

        case "build_subtree":
            guard let outline = a.str("outline") else { return "error: missing 'outline'" }
            let parent: Topic
            if let pp = a.str("parent_path") {
                guard let p = map.topic(atOutlinePath: pp) else { return "error: no parent matches 'parent_path'" }
                parent = p
            } else if let pq = a.str("parent") {
                guard let p = firstTopic(matching: pq) else { return "error: no parent matches 'parent'" }
                parent = p
            } else {
                parent = map.root ?? { let r = Topic(text: "Root"); map.root = r; return r }()
            }
            let added = Self.buildSubtree(under: parent, from: outline)
            if added > 0 { effects.mapMutated = true }
            return "added \(added) topics under \"\(parent.text)\""

        case "sort_children":
            guard let t = resolveTopic(a) else { return "error: no topic matches the given path/query" }
            guard t.children.count > 1 else { return "nothing to sort (\(t.children.count) child)" }
            t.sortChildren(ascending: !(a.bool("descending") ?? false))
            effects.mapMutated = true
            return "sorted \(t.children.count) children of \"\(t.text)\""

        default:
            return nil
        }
    }

    // MARK: - File-scoped helpers

    /// Parse an indented `outline` and attach the nested topics under `parent`.
    /// Indentation: every 2 leading spaces OR one tab counts as one level; ragged
    /// indentation is rounded to the nearest level and clamped so it never jumps
    /// more than one level deeper than the previous line. Blank lines are skipped.
    /// Returns the number of topics created.
    private static func buildSubtree(under parent: Topic, from outline: String) -> Int {
        // `stack[d]` is the most recent topic created at depth d. parent sits at
        // virtual depth -1 (stack index 0).
        var stack: [Topic] = [parent]
        var count = 0
        var prevDepth = -1
        for rawLine in outline.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Count leading indentation: a tab = one level, two spaces = one level.
            var levels = 0
            var spaceRun = 0
            for ch in line {
                if ch == "\t" {
                    levels += 1
                    spaceRun = 0
                } else if ch == " " {
                    spaceRun += 1
                    if spaceRun == 2 { levels += 1; spaceRun = 0 }
                } else {
                    break
                }
            }
            // A leftover single space is ragged indentation, not a new level —
            // ignore it (levels come in whole 2-space / tab units).

            // Clamp so depth never jumps more than one past the previous line.
            var depth = levels
            if depth > prevDepth + 1 { depth = prevDepth + 1 }
            if depth < 0 { depth = 0 }

            // The attach point is the most recent topic at depth-1 (stack[depth]).
            let parentIndex = min(depth, stack.count - 1)
            let attachTo = stack[parentIndex]
            let node = attachTo.addChild(text: trimmed)
            count += 1

            let nodeDepth = parentIndex   // node lives one level below its parent
            // Record this node as the latest at its depth (stack index nodeDepth+1).
            let slot = nodeDepth + 1
            if slot < stack.count {
                stack[slot] = node
                stack.removeLast(stack.count - (slot + 1))
            } else {
                stack.append(node)
            }
            prevDepth = nodeDepth
        }
        return count
    }
}
