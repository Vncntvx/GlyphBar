import SwiftUI

@main
struct GlyphBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment.shared

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
            }

            CommandMenu("GlyphBar") {
                Button("Show Panel") {
                    environment.quickPanelCoordinator.show(relativeTo: nil)
                }

                Button("Open Module Management") {
                    environment.openSettings(section: .modules)
                }

                Button("Import Module...") {
                    environment.importModuleFromPanel()
                }
            }
        }
    }
}
