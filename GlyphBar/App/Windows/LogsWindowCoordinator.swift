import AppKit
import SwiftUI

@MainActor
final class LogsWindowCoordinator {
    private let logger: GlyphLogger
    private var window: NSWindow?

    init(logger: GlyphLogger) {
        self.logger = logger
    }

    func open() {
        let window = window ?? makeWindow()
        self.window = window
        window.contentView = NSHostingView(
            rootView: LogsView(logger: logger)
                .preferredColorScheme(ColorSchemeOption(rawValue: AppEnvironment.shared.settingsStore.colorScheme)?.colorScheme)
        )
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "GlyphBar Logs"
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
