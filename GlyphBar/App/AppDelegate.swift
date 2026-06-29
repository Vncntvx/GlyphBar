import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let env = AppEnvironment.shared
        env.applyActivationPolicy()
        env.applyLaunchAtLogin()

        // Host the Settings scene via the official AppKit↔SwiftUI bridge so the
        // window can be opened from AppKit entry points (status menu, deep links,
        // module events) using the supported `openSettings` action.
        let settingsScene = NSHostingSceneRepresentation {
            Settings { SettingsRootView(environment: env) }
        }
        NSApp.addSceneRepresentation(settingsScene)
        env.openSettingsAction = { settingsScene.environment.openSettings() }

        Task { @MainActor in
            env.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let value = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: value) else {
            return
        }

        Task { @MainActor in
            AppEnvironment.shared.router.route(url)
        }
    }
}
