import AppKit
import MindoModel

extension MindMapView {

    /// Resolve an `Outline.fromMindMap` target back to a topic, select it, and
    /// scroll its frame into view inside the enclosing scroll view.
    public func navigate(to target: String) {
        guard let map = mindMap, let topic = resolveTopic(target: target, in: map) else { return }
        guard let element = element(forTopic: topic) else { return }
        selectElement(element)
        scrollToVisible(element.frame.insetBy(dx: -64, dy: -64))
        if let scroll = enclosingScrollView {
            // Center the topic inside the scroll view's clip area.
            let visible = scroll.documentVisibleRect
            let target = CGPoint(
                x: max(0, element.frame.midX - visible.width / 2),
                y: max(0, element.frame.midY - visible.height / 2)
            )
            scroll.contentView.scroll(to: target)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    private func resolveTopic(target: String, in map: MindMap) -> Topic? {
        guard let root = map.root else { return nil }
        if target.isEmpty { return root }
        var current: Topic = root
        for component in target.split(separator: "/") {
            guard let index = Int(component), index >= 0, index < current.children.count else { return nil }
            current = current.children[index]
        }
        return current
    }
}
