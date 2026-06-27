import AppKit
import SwiftUI

@MainActor
final class MainWindowCoordinator {
    private let runtime: ModuleRuntime
    private let settingsStore: AppSettingsStore
    private var moduleWindow: NSWindow?

    init(runtime: ModuleRuntime, settingsStore: AppSettingsStore) {
        self.runtime = runtime
        self.settingsStore = settingsStore
    }

    func openModuleWindow(moduleID: ModuleID? = nil) {
        if let moduleID {
            runtime.setSelectedModule(moduleID)
        }

        let window = moduleWindow ?? makeModuleWindow()
        window.contentView = NSHostingView(
            rootView: ModuleDashboardWindowView(runtime: runtime)
                .preferredColorScheme(ColorSchemeOption(rawValue: settingsStore.colorScheme)?.colorScheme)
        )
        moduleWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeModuleWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "GlyphBar Modules"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed]
        return window
    }
}
