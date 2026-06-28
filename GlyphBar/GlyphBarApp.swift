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
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") {
                    environment.openSettings(section: .general)
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            CommandMenu("GlyphBar") {
                Button("Show Panel") {
                    environment.quickPanelCoordinator.show(relativeTo: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Open Module Management") {
                    environment.openSettings(section: .modules)
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button("Import Module...") {
                    environment.importModuleFromPanel()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
        }
    }
}
