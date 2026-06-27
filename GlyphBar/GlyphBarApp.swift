import SwiftUI

@main
struct GlyphBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var environment = AppEnvironment.shared

    var body: some Scene {
        Settings {
            SettingsRootView(environment: environment)
                .onOpenURL { url in
                    environment.router.route(url)
                }
        }

        Window("GlyphBar", id: "main") {
            QuickPanelRootView(runtime: environment.runtime, coordinator: environment.quickPanelCoordinator)
                .frame(minWidth: 680, minHeight: 460)
                .onOpenURL { url in
                    environment.router.route(url)
                }
        }
        .windowResizability(.contentSize)
    }
}
