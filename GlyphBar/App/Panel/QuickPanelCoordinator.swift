import AppKit
import SwiftUI

@MainActor
final class QuickPanelCoordinator: ObservableObject {
    private let runtime: ModuleRuntime
    private var panel: NSPanel?

    init(runtime: ModuleRuntime) {
        self.runtime = runtime
    }

    func toggle(relativeTo statusItem: NSStatusItem) {
        if panel?.isVisible == true {
            close()
        } else {
            show(relativeTo: statusItem)
        }
    }

    func show(moduleID: ModuleID) {
        runtime.setSelectedModule(moduleID)
        show(relativeTo: nil)
    }

    func show(relativeTo statusItem: NSStatusItem?) {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.contentView = NSHostingView(rootView: QuickPanelRootView(runtime: runtime, coordinator: self))
        position(panel, relativeTo: statusItem)
        panel.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
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

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = "GlyphBar"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .transient]
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    private func position(_ panel: NSPanel, relativeTo statusItem: NSStatusItem?) {
        guard let button = statusItem?.button,
              let window = button.window else {
            panel.center()
            return
        }

        let buttonFrame = window.convertToScreen(button.frame)
        var frame = panel.frame
        frame.origin.x = buttonFrame.midX - frame.width / 2
        frame.origin.y = buttonFrame.minY - frame.height - 8

        if let screen = window.screen {
            let visible = screen.visibleFrame
            frame.origin.x = min(max(frame.origin.x, visible.minX + 12), visible.maxX - frame.width - 12)
            frame.origin.y = max(frame.origin.y, visible.minY + 12)
        }

        panel.setFrame(frame, display: true)
    }
}
