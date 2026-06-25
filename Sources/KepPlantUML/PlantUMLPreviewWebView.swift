import WebKit
import KepCore

/// WKWebView that prepends our preview actions (Refresh / Copy / Export) to
/// the standard right-click menu. The item list and handler are supplied by
/// the editor coordinator; disabled items are shown but greyed (action nil),
/// so the menu advertises the capability even before a diagram renders.
final class PlantUMLPreviewWebView: WKWebView {
    var menuItemsProvider: (() -> [PreviewMenuItem])?
    var onMenuAction: ((PreviewMenuAction) -> Void)?

    init() {
        super.init(frame: .zero, configuration: PreviewWebSecurity.hardenedConfiguration())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let items = menuItemsProvider?(), !items.isEmpty else { return }
        var index = 0
        for item in items {
            let mi = NSMenuItem(
                title: item.title,
                // Disabled items get a nil action so AppKit's auto-enable
                // greys them out without us managing validateMenuItem.
                action: item.isEnabled ? #selector(handleMenuAction(_:)) : nil,
                keyEquivalent: ""
            )
            mi.target = self
            mi.representedObject = item.action.rawValue
            menu.insertItem(mi, at: index)
            index += 1
        }
        menu.insertItem(.separator(), at: index)
    }

    @objc private func handleMenuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let action = PreviewMenuAction(rawValue: raw) else { return }
        onMenuAction?(action)
    }
}
