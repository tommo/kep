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
        let svc = DiagSplitViewController()
        svc.splitView.isVertical = true
        svc.splitView.dividerStyle = .thin
        svc.splitView.autosaveName = "mindo.mainSplit"   // persists divider positions
        // DIAGNOSTIC: log geometry whenever subviews resize (incl. live drags).
        context.coordinator.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification, object: svc.splitView, queue: .main
        ) { [weak svc] _ in if let svc { SplitDiag.log("didResizeSubviews", svc) } }

        let sidebarHost = NSHostingController(rootView: AnyView(sidebar()))
        let detailHost = NSHostingController(rootView: AnyView(detail()))
        let inspectorHost = NSHostingController(rootView: AnyView(inspector()))
        // CRITICAL: by default an NSHostingController reports its SwiftUI
        // content's ideal size as `preferredContentSize`. Inside an
        // NSSplitViewController that PINS each pane to its content width — so the
        // sidebars refuse to resize, divider drags don't stick, and only the
        // flexible detail pane ever changes size (the long-standing resize bug).
        // Clearing sizingOptions hands frame control entirely to the split view,
        // which is what makes the dividers actually draggable.
        for host in [sidebarHost, detailHost, inspectorHost] {
            host.sizingOptions = []
        }
        context.coordinator.sidebarHost = sidebarHost
        context.coordinator.detailHost = detailHost
        context.coordinator.inspectorHost = inspectorHost

        // DISTINCT, ordered holding priorities are load-bearing: the detail pane
        // must be the SOLE lowest-priority (flexible) pane so it alone absorbs a
        // resize, and the two side panes must DIFFER from each other. With equal
        // side priorities, dragging one divider lets NSSplitView redistribute
        // ambiguously — moving BOTH dividers and resizing the document (the bug:
        // "dragging the right sidebar changes the entire layout"). Sidebar is
        // strictly highest so a right-divider drag trades inspector↔detail only.
        let sidebarPriority = NSLayoutConstraint.Priority(rawValue: NSLayoutConstraint.Priority.defaultHigh.rawValue + 1)

        let sb = NSSplitViewItem(viewController: sidebarHost)
        sb.canCollapse = true
        sb.minimumThickness = 170
        sb.maximumThickness = 460
        sb.holdingPriority = sidebarPriority       // strictly highest → never perturbed by an inspector drag

        let dt = NSSplitViewItem(viewController: detailHost)
        dt.minimumThickness = 320
        dt.holdingPriority = .defaultLow           // sole flexible pane → absorbs resize, gets the bulk

        let ins = NSSplitViewItem(viewController: inspectorHost)
        ins.canCollapse = true
        ins.minimumThickness = 200
        ins.maximumThickness = 440
        ins.holdingPriority = .defaultHigh         // between sidebar and detail

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
        var resizeObserver: NSObjectProtocol?
        deinit { if let o = resizeObserver { NotificationCenter.default.removeObserver(o) } }
    }
}

// MARK: - Diagnostics (temporary)

/// Logs split-view geometry on every layout pass + a live constrain hook, so we
/// can SEE — not guess — why dividers won't resize: whether the split fills the
/// window, whether panes are pinned to their fitting/intrinsic size, and what
/// position the drag actually proposes vs. lands on.
final class DiagSplitViewController: NSSplitViewController {
    override func viewDidLayout() {
        super.viewDidLayout()
        SplitDiag.log("viewDidLayout", self)
    }
    /// Fires live during a divider drag with the proposed position. Return it
    /// unchanged (no behavior change) after logging.
    override func splitView(_ splitView: NSSplitView,
                            constrainSplitPosition proposedPosition: CGFloat,
                            ofSubviewAt dividerIndex: Int) -> CGFloat {
        let pos = super.splitView(splitView, constrainSplitPosition: proposedPosition, ofSubviewAt: dividerIndex)
        NSLog("[SPLITDIAG drag] divider=%d proposed=%.1f -> constrained=%.1f (splitW=%.1f)",
              dividerIndex, proposedPosition, pos, splitView.bounds.width)
        return pos
    }
}

enum SplitDiag {
    static func log(_ tag: String, _ svc: NSSplitViewController) {
        let sv = svc.splitView
        var lines: [String] = []
        lines.append("split.frame=\(fmt(sv.frame)) translatesAM=\(sv.translatesAutoresizingMaskIntoConstraints)")
        if let sup = sv.superview {
            lines.append("superview=\(type(of: sup)) frame=\(fmt(sup.frame))")
        }
        if let win = sv.window {
            lines.append("window.contentLayoutRect=\(fmt(win.contentLayoutRect))")
        }
        for (idx, item) in svc.splitViewItems.enumerated() {
            let v = item.viewController.view
            lines.append("  [\(idx)] frame=\(fmt(v.frame)) fitting=\(sz(v.fittingSize)) intrinsic=\(sz(v.intrinsicContentSize)) " +
                         "hugH=\(v.contentHuggingPriority(for: .horizontal).rawValue) " +
                         "collapsed=\(item.isCollapsed) hold=\(item.holdingPriority.rawValue) " +
                         "min=\(Int(item.minimumThickness)) max=\(Int(item.maximumThickness))")
        }
        NSLog("[SPLITDIAG %@]\n%@", tag, lines.joined(separator: "\n"))
    }
    private static func fmt(_ r: CGRect) -> String {
        "(\(Int(r.origin.x)),\(Int(r.origin.y)) \(Int(r.width))×\(Int(r.height)))"
    }
    private static func sz(_ s: CGSize) -> String {
        "\(s.width < 0 ? "-" : String(Int(s.width)))×\(s.height < 0 ? "-" : String(Int(s.height)))"
    }
}
