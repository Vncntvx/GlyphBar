import AppKit
import Foundation

@MainActor
final class PlatformActions {
    /// Bound by `AppDelegate` to the hosted scene's `openSettings` action.
    var openSettings: (() -> Void)?

    func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func showSettingsWindow() {
        openSettings?()
        NSApp.activate()
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }
}
