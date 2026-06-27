import AppKit
import SwiftUI

@MainActor
final class QuickPanelCoordinator: ObservableObject {
    private let runtime: ModuleRuntime
    private let menuCoordinator: AppMenuCoordinator
    private let openFullWindowAction: () -> Void
    private var panel: NSPanel?
    private weak var lastStatusItem: NSStatusItem?

    /// Set by `StatusItemController` on macOS 27 so the panel can stay in sync
    /// with the expanded interface session: any path that hides the panel
    /// (close button, settings, full window, outside click) reports it here so
    /// the controller can cancel an still-active session.
    var onPanelHidden: (() -> Void)?

    /// When true, resigning key (user clicked elsewhere) closes the panel and
    /// cancels the expanded session. Enabled only on macOS 27; left false on
    /// macOS 26, where `hidesOnDeactivate` handles dismissal.
    var dismissOnResignKey = false

    init(
        runtime: ModuleRuntime,
        menuCoordinator: AppMenuCoordinator,
        openFullWindow: @escaping () -> Void = {}
    ) {
        self.runtime = runtime
        self.menuCoordinator = menuCoordinator
        self.openFullWindowAction = openFullWindow
    }

    func toggle(relativeTo statusItem: NSStatusItem) {
        lastStatusItem = statusItem
        if panel?.isVisible == true {
            close()
        } else {
            show(relativeTo: statusItem)
        }
    }

    func show(moduleID: ModuleID) {
        runtime.setSelectedModule(moduleID)
        show(relativeTo: lastStatusItem)
    }

    func show(relativeTo statusItem: NSStatusItem?) {
        if let statusItem {
            lastStatusItem = statusItem
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(
            rootView: QuickPanelRootView(runtime: runtime, coordinator: self)
                .frame(width: 404, height: 500)
        )
        position(panel, relativeTo: statusItem)
        panel.orderFrontRegardless()
        AppEnvironment.shared.logger.statusItem("popover show")
    }

    func close() {
        let wasVisible = panel?.isVisible == true
        if wasVisible {
            panel?.orderOut(nil)
            AppEnvironment.shared.logger.statusItem("popover close")
        }
        // Notify unconditionally so the controller can cancel a still-active
        // expanded session even when the panel was already hidden by AppKit
        // (e.g. hidesOnDeactivate on app deactivation). Without this, the
        // session stays "active" after an auto-hide and subsequent left-clicks
        // stop showing the panel until the app is restarted.
        onPanelHidden?()
    }

    /// Base value for the panel's hidesOnDeactivate. Defaults to true (macOS 26
    /// and earlier: auto-hide on app deactivation). Set to false on macOS 27,
    /// where AppKit auto-hiding the panel desyncs the expanded interface
    /// session — the panel disappears while the session stays "active", leaving
    /// the menu bar unclickable until restart. On 27 the session plus
    /// didResignActive manage dismissal instead.
    var panelHidesOnDeactivate = true

    private var _isPinned = false

    func pin() {
        guard let panel else {
            return
        }
        _isPinned.toggle()
        if panelHidesOnDeactivate {
            // macOS 26: toggle the panel's auto-hide so a pinned panel stays
            // open across app deactivation.
            panel.hidesOnDeactivate = !_isPinned
        }
        // macOS 27: the panel never auto-hides; _isPinned alone gates whether
        // didResignActive cancels the expanded session on deactivation.
    }

    /// True when the user has pinned the panel (it should survive app
    /// deactivation instead of auto-dismissing).
    var isPinned: Bool {
        _isPinned
    }

    func openFullWindow() {
        close()
        openFullWindowAction()
    }

    func openSettings() {
        close()
        AppEnvironment.shared.openSettings(section: .general)
    }

    /// Fallback entry point for the context menu, surfaced from a "More" button
    /// inside the quick panel. On macOS 27 Beta the status item's secondary
    /// (right-click) gesture may not be forwarded by the system, so the menu
    /// must remain reachable from within the panel itself.
    func showMoreMenu() {
        let menu = menuCoordinator.makeMenu()
        guard let panel, panel.isVisible else {
            return
        }
        // Anchor at the panel's top-trailing corner; the system flips the menu
        // to stay on screen. Coordinates are in screen space (in: nil).
        let anchor = NSPoint(x: panel.frame.maxX, y: panel.frame.maxY - 4)
        menu.popUp(positioning: nil, at: anchor, in: nil)
    }

    private func handlePanelResignedKey() {
        // Pinned panels stay open across focus changes.
        guard dismissOnResignKey, !isPinned else {
            return
        }
        // The panel lost focus (user clicked elsewhere): close it. close()
        // funnels through onPanelHidden so the controller cancels the active
        // expanded session (→ didEnd). No delay, no event monitor — just close
        // on focus loss, the standard accessory-app dismissal.
        close()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 404, height: 500),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = "GlyphBar"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = panelHidesOnDeactivate
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        // Install the resignKey observer exactly once, tied to this panel's
        // creation. The block captures self weakly (no retain cycle) and no-ops
        // after the coordinator is deallocated; the panel lives for the app's
        // lifetime, so explicit removal is unnecessary.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePanelResignedKey()
            }
        }
        return panel
    }

    private func position(_ panel: NSPanel, relativeTo statusItem: NSStatusItem?) {
        guard let button = statusItem?.button,
              let window = button.window else {
            panel.center()
            return
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrame = window.convertToScreen(buttonFrameInWindow)
        var frame = panel.frame
        let verticalGap: CGFloat = 2
        frame.origin.x = buttonFrame.midX - frame.width / 2
        frame.origin.y = buttonFrame.minY - frame.height - verticalGap

        if let screen = window.screen {
            let visible = screen.visibleFrame
            frame.origin.x = min(max(frame.origin.x, visible.minX + 12), visible.maxX - frame.width - 12)
            frame.origin.y = max(frame.origin.y, visible.minY + 12)
        }

        panel.setFrame(frame, display: true)
    }
}
