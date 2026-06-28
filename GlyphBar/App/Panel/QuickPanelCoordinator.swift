import AppKit
import SwiftUI
import Combine

@MainActor
final class QuickPanelCoordinator: ObservableObject {
    private let runtime: ModuleRuntime
    private let menuCoordinator: AppMenuCoordinator
    private let settingsStore: AppSettingsStore
    private var panel: NSPanel?
    private weak var lastStatusItem: NSStatusItem?

    var onPanelHidden: (() -> Void)?
    var dismissOnResignKey = false

    /// Reflects pinPanel from settings store for view binding.
    var isPinned: Bool { settingsStore.pinPanel }

    /// Base value for the panel's hidesOnDeactivate. Defaults to true (macOS 26
    /// and earlier: auto-hide on app deactivation). Set to false on macOS 27,
    /// where AppKit auto-hiding the panel desyncs the expanded interface
    /// session — the panel disappears while the session stays "active", leaving
    /// the menu bar unclickable until restart. On 27 the session plus
    /// didResignActive manage dismissal instead.
    var panelHidesOnDeactivate = true

    init(
        runtime: ModuleRuntime,
        menuCoordinator: AppMenuCoordinator,
        settingsStore: AppSettingsStore
    ) {
        self.runtime = runtime
        self.menuCoordinator = menuCoordinator
        self.settingsStore = settingsStore
        // Propagate settingsStore changes so views observing coordinator refresh.
        settingsStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

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
                .frame(width: 404)
                .preferredColorScheme(ColorSchemeOption(rawValue: settingsStore.colorScheme)?.colorScheme)
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

    func pin() {
        settingsStore.pinPanel.toggle()
        panel?.hidesOnDeactivate = panelHidesOnDeactivate && !settingsStore.pinPanel
    }

    /// Apply the persisted pin preference to the live panel (called from Settings).
    func applyPinPreference() {
        panel?.hidesOnDeactivate = panelHidesOnDeactivate && !settingsStore.pinPanel
    }

    func resizePanel(to size: CGSize) {
        guard let panel else { return }
        var f = panel.frame
        let newHeight = min(max(size.height, 200), 750)
        guard abs(f.size.height - newHeight) > 4 else { return }
        f.origin.y += f.size.height - newHeight
        f.size.height = newHeight
        panel.setFrame(f, display: false, animate: false)
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
        guard dismissOnResignKey, !settingsStore.pinPanel else {
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
            contentRect: NSRect(x: 0, y: 0, width: 404, height: 400),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = panelHidesOnDeactivate && !settingsStore.pinPanel
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
              let window = button.window,
              let screen = window.screen else {
            panel.center()
            return
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrame = window.convertToScreen(buttonFrameInWindow)
        let visible = screen.visibleFrame
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height

        let originX = min(max(buttonFrame.midX - panelWidth / 2, visible.minX + 12), visible.maxX - panelWidth - 12)
        let originY = visible.maxY - panelHeight

        AppEnvironment.shared.logger.statusItem("panel position intent: visible.maxY=\(visible.maxY), height=\(panelHeight), originY=\(originY), top=\(originY + panelHeight)")

        panel.setFrame(NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight), display: false)

        let actual = panel.frame
        AppEnvironment.shared.logger.statusItem("panel position actual: frame=\(actual), top=\(actual.maxY), contentFrame=\(panel.contentView?.frame ?? .zero)")
    }
}

// MARK: - Adaptive Panel Height

private struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct ResizeModifier: ViewModifier {
    let onResize: (CGSize) -> Void
    func body(content: Content) -> some View {
        content
            .background(GeometryReader { geo in
                Color.clear.preference(key: HeightKey.self, value: geo.size.height)
            })
            .onPreferenceChange(HeightKey.self) { height in
                if height > 0 { onResize(CGSize(width: 404, height: height)) }
            }
    }
}

extension View {
    func onResize(_ action: @escaping (CGSize) -> Void) -> some View {
        modifier(ResizeModifier(onResize: action))
    }
}
