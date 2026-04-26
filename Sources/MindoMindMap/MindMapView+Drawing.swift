import AppKit
import MindoCore
import MindoModel

/// Drawing helpers for `MindMapView`. Lifted out of the main file to keep
/// the canvas core (init / state / responder / hit-testing) compact. The
/// `draw(_:)` entry point itself stays in MindMapView.swift because it
/// touches private drag-state for the ghost overlay.
extension MindMapView {

    /// Render one topic: rounded rect + drop shadow + border + embedded
    /// image (if any) + text + extras strip + collapse marker.
    func drawElement(_ el: MindMapElement, into ctx: CGContext) {
        let level = el.level
        let path = CGPath(
            roundedRect: el.frame,
            cornerWidth: theme.cornerRadius,
            cornerHeight: theme.cornerRadius,
            transform: nil
        )

        // Fill (with drop shadow on non-root levels).
        let fill = el.customFillColor ?? theme.fillColor(forLevel: level)
        ctx.saveGState()
        if level > 0 {
            ctx.setShadow(offset: theme.dropShadowOffset, blur: 4, color: NSColor.black.withAlphaComponent(theme.dropShadowOpacity).cgColor)
        }
        ctx.addPath(path)
        ctx.setFillColor(fill.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Border.
        ctx.addPath(path)
        ctx.setStrokeColor((el.customBorderColor ?? theme.borderColor(forLevel: level)).cgColor)
        ctx.setLineWidth(1.0)
        ctx.strokePath()

        // Embedded image (above the text).
        if let image = el.embeddedImage {
            let imageRect = el.embeddedImageDrawRect
            ctx.saveGState()
            ctx.interpolationQuality = .high
            image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1)
            ctx.restoreGState()
        }

        // Text — leaves room on the right for the extra-icons strip.
        let font = theme.font(forLevel: level)
        let style = NSMutableParagraphStyle()
        // Per-topic alignment override (TopicAttribute.textAlign), defaults
        // to center to match historical Mindo behaviour.
        style.alignment = TopicTextAlign.from(attribute: el.topic.attribute(TopicAttribute.textAlign)).nsAlignment
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: el.customTextColor ?? theme.textColor(forLevel: level),
            .paragraphStyle: style,
        ]
        var textRect = el.frame.insetBy(dx: theme.textInsets.left, dy: theme.textInsets.top)
        if el.extraIconStripWidth > 0 {
            textRect.size.width = max(0, textRect.width - el.extraIconStripWidth)
        }
        if el.embeddedImageHeight > 0 {
            textRect.origin.y += el.embeddedImageHeight
            textRect.size.height = max(0, textRect.height - el.embeddedImageHeight)
        }

        // Inline emoticon, drawn left of the title. Layout reserved width
        // for it via emoticonLeadingWidth; we just shift the text rect.
        if let name = el.emoticonName,
           let icon = MindMapEmoticon.image(
                for: name,
                pointSize: MindMapElement.emoticonSize,
                color: el.customTextColor ?? theme.textColor(forLevel: level)
           ) {
            let iconY = textRect.midY - icon.size.height / 2
            icon.draw(in: CGRect(x: textRect.minX, y: iconY, width: icon.size.width, height: icon.size.height))
            let inset = el.emoticonLeadingWidth
            textRect.origin.x += inset
            textRect.size.width = max(0, textRect.width - inset)
        }

        let displayText = el.topic.text.isEmpty ? "·" : el.topic.text
        (displayText as NSString).draw(in: textRect, withAttributes: attrs)

        // Extras strip.
        for (type, rect) in el.extraIconRects {
            drawExtraIcon(type: type, in: rect, level: level, into: ctx)
        }

        // Collapse marker (small caret on the side facing children).
        if el.isCollapsed && !el.children.isEmpty {
            let marker = "+"
            let mAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 10),
                .foregroundColor: theme.borderColor(forLevel: level),
            ]
            let size = (marker as NSString).size(withAttributes: mAttrs)
            let x = el.isLeftSide ? el.frame.minX - size.width - 4 : el.frame.maxX + 4
            (marker as NSString).draw(at: CGPoint(x: x, y: el.frame.midY - size.height / 2), withAttributes: mAttrs)
        }
    }

    /// Recursively walk the tree and draw a parent→child connector for
    /// every visible edge. Root has its left/right children handled
    /// explicitly (so each side's connectors anchor on the matching root edge).
    func drawConnectors(from element: MindMapElement, into ctx: CGContext) {
        if element.level == 0, let root = rootElement, root === element {
            for child in root.leftChildren { drawConnector(from: root, to: child, into: ctx); drawConnectors(from: child, into: ctx) }
            for child in root.rightChildren { drawConnector(from: root, to: child, into: ctx); drawConnectors(from: child, into: ctx) }
            return
        }
        guard !element.isCollapsed else { return }
        for child in element.children {
            drawConnector(from: element, to: child, into: ctx)
            drawConnectors(from: child, into: ctx)
        }
    }

    /// Render an SF Symbol-based icon for one extra type inside `rect`,
    /// tinted to match the topic's text color so it reads on every theme.
    func drawExtraIcon(type: ExtraType, in rect: CGRect, level: Int, into ctx: CGContext) {
        let symbolName: String
        switch type {
        case .note:  symbolName = "note.text"
        case .link:  symbolName = "link"
        case .file:  symbolName = "paperclip"
        case .topic: symbolName = "arrow.uturn.right.circle"
        case .unknown: symbolName = "questionmark.circle"
        }
        let config = NSImage.SymbolConfiguration(pointSize: rect.width - 2, weight: .medium)
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let tint = theme.textColor(forLevel: level).withAlphaComponent(0.85)
        let tinted = image.copy() as! NSImage
        tinted.lockFocus()
        tint.set()
        let imageRect = NSRect(origin: .zero, size: tinted.size)
        imageRect.fill(using: .sourceAtop)
        tinted.unlockFocus()
        let drawRect = CGRect(
            x: rect.midX - tinted.size.width / 2,
            y: rect.midY - tinted.size.height / 2,
            width: tinted.size.width, height: tinted.size.height
        )
        tinted.draw(in: drawRect)
    }

    /// Draw a dashed cubic-bezier arrow for every topic that has an
    /// ExtraTopic pointing to another topic in the same map. Mirrors
    /// `mindmap-panel`'s "jump" overlay.
    func drawJumpArrows(rootElement: MindMapElement, into ctx: CGContext) {
        guard let map = mindMap else { return }
        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.setStrokeColor(NSColor.systemPurple.withAlphaComponent(0.85).cgColor)
        ctx.setFillColor(NSColor.systemPurple.cgColor)
        ctx.setLineWidth(1.2)
        rootElement.traverse { el in
            guard let extra = el.topic.extra(.topic) as? ExtraTopic,
                  let target = map.findTopic(uid: extra.value),
                  let targetEl = element(forTopic: target) else { return }
            drawJumpArrow(from: el, to: targetEl, into: ctx)
        }
        ctx.restoreGState()
    }

    func drawJumpArrow(from a: MindMapElement, to b: MindMapElement, into ctx: CGContext) {
        let start = CGPoint(x: a.frame.midX, y: a.frame.midY)
        let end = CGPoint(x: b.frame.midX, y: b.frame.midY)
        // Anchor the line on the box edges so it doesn't disappear under the
        // topic rects.
        let p1 = clip(point: start, against: a.frame, towards: end)
        let p2 = clip(point: end, against: b.frame, towards: start)
        let dx = p2.x - p1.x, dy = p2.y - p1.y
        // Bow the arc out by 30% of the chord length so curves don't overlap
        // straight connectors.
        let bowOffset = max(28, hypot(dx, dy) * 0.30)
        let cx = (p1.x + p2.x) / 2 + (-dy / hypot(dx, dy)) * bowOffset
        let cy = (p1.y + p2.y) / 2 + (dx / hypot(dx, dy)) * bowOffset

        ctx.beginPath()
        ctx.move(to: p1)
        ctx.addQuadCurve(to: p2, control: CGPoint(x: cx, y: cy))
        ctx.strokePath()

        // Arrow head at p2.
        let head: CGFloat = 9
        let angle = atan2(p2.y - cy, p2.x - cx)
        let h1 = CGPoint(x: p2.x - head * cos(angle - .pi / 6), y: p2.y - head * sin(angle - .pi / 6))
        let h2 = CGPoint(x: p2.x - head * cos(angle + .pi / 6), y: p2.y - head * sin(angle + .pi / 6))
        ctx.beginPath()
        ctx.move(to: p2); ctx.addLine(to: h1); ctx.addLine(to: h2); ctx.closePath()
        ctx.fillPath()
    }

    /// Stroke a rounded outline that hugs `frame`, expanded outward by
    /// `inset`. The corner radius grows with the inset so concentric outlines
    /// (selection / drop-target / multi-select halo) stay visually balanced.
    /// Caller pre-sets `setStrokeColor` and `setLineWidth`.
    func strokeRoundedOutline(around frame: CGRect, inset: CGFloat, into ctx: CGContext) {
        let rect = frame.insetBy(dx: -inset, dy: -inset)
        let radius = theme.cornerRadius + inset
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.strokePath()
    }

    /// Clip a line endpoint to the rectangle's edge along the line towards `away`.
    func clip(point: CGPoint, against rect: CGRect, towards away: CGPoint) -> CGPoint {
        let dx = away.x - point.x, dy = away.y - point.y
        guard dx != 0 || dy != 0 else { return point }
        let length = hypot(dx, dy)
        let nx = dx / length, ny = dy / length
        // Step out along the direction until we leave the rect.
        var t: CGFloat = 0
        let step: CGFloat = 1
        while t < length, rect.contains(CGPoint(x: point.x + nx * t, y: point.y + ny * t)) {
            t += step
        }
        return CGPoint(x: point.x + nx * t, y: point.y + ny * t)
    }

    /// Draw a single parent→child connector. Style and line width come from
    /// PrefKeys so the user can swap bezier ↔ polyline at runtime.
    func drawConnector(from parent: MindMapElement, to child: MindMapElement, into ctx: CGContext) {
        // Start at the parent edge facing the child; end at the child edge facing the parent.
        let pStart: CGPoint
        let pEnd: CGPoint
        if child.isLeftSide {
            pStart = CGPoint(x: parent.frame.minX, y: parent.frame.midY)
            pEnd = CGPoint(x: child.frame.maxX, y: child.frame.midY)
        } else {
            pStart = CGPoint(x: parent.frame.maxX, y: parent.frame.midY)
            pEnd = CGPoint(x: child.frame.minX, y: child.frame.midY)
        }
        let style = ConnectorStyle.from(rawString: UserDefaults.standard.string(forKey: PrefKeys.mindmapConnectorStyle))
        let width = CGFloat(PrefKeys.double(PrefKeys.mindmapConnectorWidth, fallback: Double(theme.connectorWidth)))

        ctx.beginPath()
        ctx.move(to: pStart)
        switch style {
        case .bezier:
            let midX = (pStart.x + pEnd.x) / 2
            let c1 = CGPoint(x: midX, y: pStart.y)
            let c2 = CGPoint(x: midX, y: pEnd.y)
            ctx.addCurve(to: pEnd, control1: c1, control2: c2)
        case .polyline:
            // Two-segment elbow: horizontal halfway, then vertical to target,
            // then horizontal into the child edge. Keeps the visual depth
            // hierarchy of bezier without the curvature.
            let midX = (pStart.x + pEnd.x) / 2
            ctx.addLine(to: CGPoint(x: midX, y: pStart.y))
            ctx.addLine(to: CGPoint(x: midX, y: pEnd.y))
            ctx.addLine(to: pEnd)
        }
        ctx.setStrokeColor(theme.connectorColor.cgColor)
        ctx.setLineWidth(width)
        ctx.strokePath()
    }
}
