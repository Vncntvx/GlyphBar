import AppKit
import SwiftUI

@MainActor
final class QuickPanelCoordinator: ObservableObject {
    private let runtime: ModuleRuntime
    private let openFullWindowAction: () -> Void
    private var panel: NSPanel?
    private weak var lastStatusItem: NSStatusItem?

    init(runtime: ModuleRuntime, openFullWindow: @escaping () -> Void = {}) {
        self.runtime = runtime
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
    }

    func close() {
        panel?.orderOut(nil)
    }

    func pin() {
        guard let panel else {
            return
        }
        panel.hidesOnDeactivate.toggle()
    }

    func openFullWindow() {
        close()
        openFullWindowAction()
    }

    func openSettings() {
        close()
        AppEnvironment.shared.openSettings(section: .general)
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
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
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
