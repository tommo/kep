import SwiftUI
import AppKit

/// A sidebar | detail | inspector split backed by AppKit's NSSplitView so the
/// pane widths PERSIST (autosaveName) and the layout is stable across document
/// modes (no auto-collapse). The sidebar and inspector collapse/expand via the
/// `showSidebar` / `showInspector` flags; the detail pane holds the remaining
/// space (lowest holding priority) so it gets the bulk of the window by default.
struct ThreePaneSplit<Sidebar: View, Detail: View, Inspector: View>: NSViewControllerRepresentable {
    var showSidebar: Bool
    var showInspector: Bool
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail
    @ViewBuilder var inspector: () -> Inspector

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let svc = NSSplitViewController()
        svc.splitView.isVertical = true
        svc.splitView.dividerStyle = .thin
        svc.splitView.autosaveName = "mindo.mainSplit"   // persists divider positions

        let sidebarHost = NSHostingController(rootView: AnyView(sidebar()))
        let detailHost = NSHostingController(rootView: AnyView(detail()))
        let inspectorHost = NSHostingController(rootView: AnyView(inspector()))
        context.coordinator.sidebarHost = sidebarHost
        context.coordinator.detailHost = detailHost
        context.coordinator.inspectorHost = inspectorHost

        let sb = NSSplitViewItem(viewController: sidebarHost)
        sb.canCollapse = true
        sb.minimumThickness = 170
        sb.maximumThickness = 460
        sb.holdingPriority = .defaultHigh          // keeps its width when the window resizes

        let dt = NSSplitViewItem(viewController: detailHost)
        dt.minimumThickness = 320
        dt.holdingPriority = .defaultLow           // absorbs resize → gets the bulk of the space

        let ins = NSSplitViewItem(viewController: inspectorHost)
        ins.canCollapse = true
        ins.minimumThickness = 200
        ins.maximumThickness = 440
        ins.holdingPriority = .defaultHigh

        svc.addSplitViewItem(sb)
        svc.addSplitViewItem(dt)
        svc.addSplitViewItem(ins)
        context.coordinator.sidebarItem = sb
        context.coordinator.inspectorItem = ins

        sb.isCollapsed = !showSidebar
        ins.isCollapsed = !showInspector

        // Sensible first-run widths (autosave overrides these once the user has
        // dragged): a slim sidebar + inspector so the document gets the rest.
        DispatchQueue.main.async {
            guard svc.splitView.autosaveName == nil ||
                  UserDefaults.standard.object(forKey: "NSSplitView Subview Frames mindo.mainSplit") == nil
            else { return }
            svc.splitView.setPosition(220, ofDividerAt: 0)
            let w = svc.splitView.bounds.width
            if w > 0 { svc.splitView.setPosition(w - 250, ofDividerAt: 1) }
        }
        return svc
    }

    func updateNSViewController(_ svc: NSSplitViewController, context: Context) {
        // Push the latest SwiftUI content so state changes flow through.
        context.coordinator.sidebarHost?.rootView = AnyView(sidebar())
        context.coordinator.detailHost?.rootView = AnyView(detail())
        context.coordinator.inspectorHost?.rootView = AnyView(inspector())
        if let sb = context.coordinator.sidebarItem, sb.isCollapsed == showSidebar {
            sb.isCollapsed = !showSidebar
        }
        if let ins = context.coordinator.inspectorItem, ins.isCollapsed == showInspector {
            ins.isCollapsed = !showInspector
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var sidebarHost: NSHostingController<AnyView>?
        var detailHost: NSHostingController<AnyView>?
        var inspectorHost: NSHostingController<AnyView>?
        var sidebarItem: NSSplitViewItem?
        var inspectorItem: NSSplitViewItem?
    }
}
